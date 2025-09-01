dependency "kubernetes" {
  config_path = find_in_parent_folders("kubernetes")
}

locals {
  env_vars    = jsondecode(read_tfvars_file(find_in_parent_folders("env.tfvars")))
  global_vars = jsondecode(read_tfvars_file(find_in_parent_folders("global.tfvars")))
}

generate "terraform" {
  contents  = <<-EOF
    terraform {
      required_providers {
        google = {
          source  = "hashicorp/google"
          version = "~> 7.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.0"
        }
      }
      required_version = "~> 1.0"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "terraform.tf"
}

generate "providers" {
  contents  = <<-EOF
    provider "google" {
      project = "${local.env_vars.gcp_project_id}"
      region  = "${local.env_vars.gcp_region}"
    }

    data "google_client_config" "current" {}

    provider "helm" {
      kubernetes = {
        host  = ${jsonencode(dependency.kubernetes.outputs.control_plane_endpoint)}
        token = data.google_client_config.current.access_token
      }
    }

    provider "kubernetes" {
      host  = ${jsonencode(dependency.kubernetes.outputs.control_plane_endpoint)}
      token = data.google_client_config.current.access_token
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "providers.tf"
}

generate "main" {
  contents  = <<-EOF
    module "karpenter_operator" {
      cluster_location          = ${jsonencode(local.env_vars.kubernetes_cluster_location)}
      cluster_name              = ${jsonencode(local.env_vars.kubernetes_cluster_name)}
      karpenter_version         = ${jsonencode(local.env_vars.karpenter_version)}
      node_service_account_name = ${jsonencode(dependency.kubernetes.outputs.node_service_account_name)}
      source                    = "${find_in_parent_folders("modules")}/karpenter-operator"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "main.tf"
}
