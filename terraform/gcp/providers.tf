# Same idea as terraform/azure/providers.tf - which Terraform version this
# project expects, and which provider plugin knows how to talk to GCP's
# API. A completely different cloud, but Terraform's own job here doesn't
# change at all - that's rather the point being demonstrated.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  # us-central1 - not europe-west3 - is deliberate: GCP's Always Free tier
  # for this VM size is region-locked to us-central1, us-west1, or
  # us-east1. Building this anywhere else would mean real, if small,
  # ongoing charges - exactly what the project's own cost rule forbids.
  region = "us-central1"
  zone   = "us-central1-a"
}
