terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    wireguard = {
      source  = "OJFord/wireguard"
      version = "~> 0.4"
    }
  }
  required_version = "~> 1.0"
}
