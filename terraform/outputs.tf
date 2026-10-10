output "raw_bucket" {
  value = google_storage_bucket.raw.url
}

output "vertex_connection" {
  description = "Use as `region.connection_id` in AI.GENERATE / CREATE MODEL."
  value       = "${var.region}.${google_bigquery_connection.vertex.connection_id}"
}

output "artifact_registry" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "service_accounts" {
  value = { for k, sa in google_service_account.sa : k => sa.email }
}

output "run_pipeline" {
  description = "Run the whole pipeline end to end."
  value       = "gcloud workflows run ${google_workflows_workflow.e2e.name} --location=${var.region}"
}
