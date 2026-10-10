# Cloud Run jobs. Images are built by Cloud Build (`gcloud builds submit <dir> --tag ...`);
# Terraform owns the job definitions. Jobs bill only while running.

locals {
  image_repo = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

resource "google_cloud_run_v2_job" "loader" {
  name                = "globalmart-loader"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [client, client_version, template[0].template[0].containers[0].image] # image: set by CI
  }

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

resource "google_cloud_run_v2_job" "dbt" {
  name                = "globalmart-dbt"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [client, client_version, template[0].template[0].containers[0].image] # image: set by CI
  }

  template {
    task_count = 1
    template {
      service_account = google_service_account.sa["dbt"].email
      timeout         = "3600s"
      max_retries     = 0 # a failed test must stop the pipeline, not be retried

      containers {
        image = "${local.image_repo}/dbt:latest"
        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "RAW_BUCKET"
          value = google_storage_bucket.raw.name
        }
        resources {
          limits = { cpu = "2", memory = "2Gi" }
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

# --- App: Cloud Run service (React + Express) ---------------------------------
# Requires authentication (no allUsers): open it with
#   gcloud run services proxy globalmart-app --region=us-central1
# IAP needs an OAuth consent screen on a personal project (no organisation), so the
# fallback is Cloud Run IAM; grant more users roles/run.invoker via var.app_users.
resource "google_cloud_run_v2_service" "app" {
  name                = "globalmart-app"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  # New image revisions are rolled out with `gcloud run deploy` (Phase 8: Cloud Build).
  lifecycle {
    ignore_changes = [client, client_version, template[0].containers[0].image] # image: set by CI
  }

  template {
    service_account = google_service_account.sa["app"].email
    scaling {
      min_instance_count = 0 # bills only while serving
      max_instance_count = 2
    }
    containers {
      image = "${local.image_repo}/app:latest"
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "AGENT_ID"
        value = "globalmart-agent"
      }
      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "app_invokers" {
  for_each = toset(var.app_users)
  name     = google_cloud_run_v2_service.app.name
  location = var.region
  role     = "roles/run.invoker"
  member   = each.value
}
