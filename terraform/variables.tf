variable "project_id" {
  description = "GCP project ID (globally unique)."
  type        = string
}

variable "region" {
  description = "Region for the bucket, datasets, Artifact Registry and Cloud Run."
  type        = string
  default     = "us-central1"
}

variable "datasets" {
  description = "BigQuery datasets, one per medallion layer plus ops."
  type        = map(string)
  default = {
    bronze  = "Raw source files, every column STRING"
    silver  = "Cleaned entities, rejected_records and pipeline_audit_log"
    gold    = "Dimensional model, views and GenAI outputs"
    metrics = "Business metric aggregations"
    ops     = "Pipeline operations: ingest_log and run history"
  }
}

variable "app_users" {
  description = "Principals allowed to open the app (roles/run.invoker), e.g. user:me@gmail.com. Project owners can already."
  type        = list(string)
  default     = []
}
