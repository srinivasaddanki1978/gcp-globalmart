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
  description = "BigQuery datasets, mirroring the Databricks schemas."
  type        = map(string)
  default = {
    bronze  = "Raw source files, every column STRING (Auto Loader equivalent)"
    silver  = "Cleaned entities, rejected_records and pipeline_audit_log"
    gold    = "Dimensional model, views and GenAI outputs"
    metrics = "Business metric aggregations"
    ops     = "Pipeline operations: ingest_log and run history"
  }
}
