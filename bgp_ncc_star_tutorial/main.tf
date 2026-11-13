terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 6.48.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "= 6.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}


data "google_compute_zones" "main" {}


locals {
  prefix = var.prefix != null && var.prefix != "" ? "${var.prefix}-" : ""
}