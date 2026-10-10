# Cloud Workflows: the single end-to-end trigger (loader -> dbt).

resource "google_service_account" "workflows" {
  account_id   = "sa-workflows"
  display_name = "GlobalMart end-to-end workflow"
}

# Run exactly these two jobs and read their executions; nothing else.
resource "google_cloud_run_v2_job_iam_member" "workflows_run" {
  for_each = {
    loader = google_cloud_run_v2_job.loader.name
    dbt    = google_cloud_run_v2_job.dbt.name
  }
  name     = each.value
  location = var.region
  role     = "roles/run.invoker"
  member   = google_service_account.workflows.member
}

resource "google_project_iam_member" "workflows_run_viewer" {
  project = var.project_id
  role    = "roles/run.viewer"
  member  = google_service_account.workflows.member
}

resource "google_project_iam_member" "workflows_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = google_service_account.workflows.member
}

resource "google_workflows_workflow" "e2e" {
  name            = "globalmart-e2e"
  region          = var.region
  description     = "Bronze loader, then dbt build (silver, gold, metrics, tests)"
  service_account = google_service_account.workflows.id
  call_log_level  = "LOG_ERRORS_ONLY"
  source_contents = templatefile("${path.module}/../workflows/globalmart_e2e.yaml", {
    project = var.project_id
    region  = var.region
    loader  = google_cloud_run_v2_job.loader.name
    dbt     = google_cloud_run_v2_job.dbt.name
  })

  depends_on = [google_project_service.apis]
}
