terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
  required_version = "~> 1.0"
}
