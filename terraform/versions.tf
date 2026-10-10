terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  # Local state for the lab. Move to a GCS backend if more than one person applies.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
