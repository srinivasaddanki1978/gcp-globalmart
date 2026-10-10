# Cloud Run jobs. Images are built by Cloud Build (`gcloud builds submit <dir> --tag ...`);
# Terraform owns the job definitions. Jobs bill only while running.

locals {
  image_repo = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

resource "google_cloud_run_v2_job" "loader" {
  name                = "globalmart-loader"
  location            = var.region
  deletion_protection = false

  template {
    task_count = 1
    template {
      service_account = google_service_account.sa["loader"].email
      timeout         = "1800s"
      max_retries     = 1 # safe: the loader skips files already in ops.ingest_log

      containers {
        image = "${local.image_repo}/loader:latest"
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "RAW_BUCKET"
          value = google_storage_bucket.raw.name
        }
        env {
          name  = "BQ_LOCATION"
          value = var.region
        }
        resources {
          limits = { cpu = "1", memory = "1Gi" }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}
