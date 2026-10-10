# Phase 0 foundations: APIs, raw bucket, datasets, Artifact Registry, service accounts,
# IAM and the BigQuery -> Vertex AI connection. Cloud Run jobs, Workflows and the
# budget are added in later phases.

locals {
  apis = [
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "workflows.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
  ]

  # Dataset-level roles per service account.
  dataset_access = {
    loader_bronze = { sa = "loader", dataset = "bronze", role = "roles/bigquery.dataEditor" }
    loader_ops    = { sa = "loader", dataset = "ops", role = "roles/bigquery.dataEditor" }
    dbt_bronze    = { sa = "dbt", dataset = "bronze", role = "roles/bigquery.dataViewer" }
    dbt_ops       = { sa = "dbt", dataset = "ops", role = "roles/bigquery.dataViewer" }
    dbt_silver    = { sa = "dbt", dataset = "silver", role = "roles/bigquery.dataEditor" }
    dbt_gold      = { sa = "dbt", dataset = "gold", role = "roles/bigquery.dataEditor" }
    dbt_metrics   = { sa = "dbt", dataset = "metrics", role = "roles/bigquery.dataEditor" }
    app_gold      = { sa = "app", dataset = "gold", role = "roles/bigquery.dataViewer" }
  }
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# --- Storage -----------------------------------------------------------------

resource "google_storage_bucket" "raw" {
  name                        = "${var.project_id}-globalmart-raw"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true # lab: lets `terraform destroy` remove the uploaded files

  depends_on = [google_project_service.apis]
}

# --- BigQuery ------------------------------------------------------------------

resource "google_bigquery_dataset" "ds" {
  for_each                   = var.datasets
  dataset_id                 = each.key
  description                = each.value
  location                   = var.region
  delete_contents_on_destroy = true # lab: teardown removes tables too

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_connection" "vertex" {
  connection_id = "vertex-ai"
  location      = var.region
  friendly_name = "Vertex AI (Gemini, embeddings)"
  cloud_resource {}

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "connection_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_bigquery_connection.vertex.cloud_resource[0].service_account_id}"
}

# --- Artifact Registry ---------------------------------------------------------

resource "google_artifact_registry_repository" "images" {
  repository_id = "globalmart"
  location      = var.region
  format        = "DOCKER"
  description   = "Images for the loader, dbt and app"

  depends_on = [google_project_service.apis]
}

# --- Service accounts and IAM --------------------------------------------------

resource "google_service_account" "sa" {
  for_each = {
    loader = "Bronze loader (Cloud Run job)"
    dbt    = "dbt build (Cloud Run job)"
    app    = "Dashboard app (Cloud Run service), read-only gold"
  }
  account_id   = "sa-${each.key}"
  display_name = each.value

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "job_user" {
  for_each = google_service_account.sa
  project  = var.project_id
  role     = "roles/bigquery.jobUser"
  member   = each.value.member
}

resource "google_bigquery_dataset_iam_member" "access" {
  for_each   = local.dataset_access
  dataset_id = google_bigquery_dataset.ds[each.value.dataset].dataset_id
  role       = each.value.role
  member     = google_service_account.sa[each.value.sa].member
}

# dbt calls Gemini / embeddings through the connection.
resource "google_bigquery_connection_iam_member" "dbt_connection_user" {
  connection_id = google_bigquery_connection.vertex.connection_id
  location      = var.region
  role          = "roles/bigquery.connectionUser"
  member        = google_service_account.sa["dbt"].member
}

# Loader reads source files; dbt writes run_results.json history.
resource "google_storage_bucket_iam_member" "loader_read" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.sa["loader"].member
}

resource "google_storage_bucket_iam_member" "dbt_write" {
  bucket = google_storage_bucket.raw.name
  role   = "roles/storage.objectCreator"
  member = google_service_account.sa["dbt"].member
}
