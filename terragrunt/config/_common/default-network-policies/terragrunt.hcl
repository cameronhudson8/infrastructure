dependency "kubernetes_cluster" {
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

    provider "kubernetes" {
      cluster_ca_certificate = ${jsonencode(dependency.kubernetes_cluster.outputs.control_plane_ca_certificate)}
      host                   = ${jsonencode(dependency.kubernetes_cluster.outputs.control_plane_endpoint)}
      token                  = data.google_client_config.current.access_token
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "providers.tf"
}

generate "main" {
  contents  = <<-EOF
    module "default_network_policies" {
      source = "${find_in_parent_folders("modules")}/default-network-policies"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "main.tf"
}

generate "outputs" {
  contents  = <<-EOF
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "outputs.tf"
}
