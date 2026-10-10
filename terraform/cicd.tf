# CI/CD: Cloud Build on every push to main (cloudbuild.yaml at the repo root).
# Tests -> dbt CI build into *_ci datasets -> images -> deploy. Runs as sa-cloudbuild.

# CI datasets: changed dbt models build here (dbt target ci). Tables expire after 3 days.
resource "google_bigquery_dataset" "ci" {
  for_each                    = toset(["silver_ci", "gold_ci", "metrics_ci"])
  dataset_id                  = each.value
  description                 = "dbt CI builds (state:modified+); temporary"
  location                    = var.region
  default_table_expiration_ms = 3 * 24 * 3600 * 1000
  delete_contents_on_destroy  = true

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "cloudbuild" {
  account_id   = "sa-cloudbuild"
  display_name = "Cloud Build CI/CD"
}

locals {
  cloudbuild_project_roles = [
    "roles/bigquery.jobUser",       # dbt CI, docs, query dry runs
    "roles/run.developer",          # deploy the app, update job images
    "roles/logging.logWriter",      # build logs (CLOUD_LOGGING_ONLY)
    "roles/artifactregistry.writer" # push images
  ]
}

resource "google_project_iam_member" "cloudbuild" {
  for_each = toset(local.cloudbuild_project_roles)
  project  = var.project_id
  role     = each.value
  member   = google_service_account.cloudbuild.member
}

# Read production datasets (dbt --defer, docs catalog, app query check)...
resource "google_bigquery_dataset_iam_member" "cloudbuild_read" {
  for_each   = toset(["bronze", "silver", "gold", "metrics", "ops"])
  dataset_id = google_bigquery_dataset.ds[each.value].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = google_service_account.cloudbuild.member
}

# ...and write only the CI datasets.
resource "google_bigquery_dataset_iam_member" "cloudbuild_ci_write" {
  for_each   = google_bigquery_dataset.ci
  dataset_id = each.value.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_service_account.cloudbuild.member
}

# Changed GenAI models call Gemini through the connection.
resource "google_bigquery_connection_iam_member" "cloudbuild_connection_user" {
  connection_id = google_bigquery_connection.vertex.connection_id
  location      = var.region
  role          = "roles/bigquery.connectionUser"
  member        = google_service_account.cloudbuild.member
}

# Production dbt manifest (state for state:modified).
resource "google_storage_bucket_iam_member" "cloudbuild_state_read" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.cloudbuild.member
}

# Deploying a service/job that runs as another service account requires actAs on it.
resource "google_service_account_iam_member" "cloudbuild_act_as" {
  for_each           = google_service_account.sa
  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.cloudbuild.member
}

# Manual runs (`gcloud builds submit`) stage the source in <project>_cloudbuild.
resource "google_storage_bucket_iam_member" "cloudbuild_source_read" {
  bucket = "${var.project_id}_cloudbuild"
  role   = "roles/storage.objectViewer"
  member = google_service_account.cloudbuild.member
}
