dependency "vpc" {
  config_path = "../vpc"
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
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "providers.tf"
}

generate "main" {
  contents  = <<-EOF
    module "kubernetes_cluster" {
      env_name                                        = ${jsonencode(local.env_vars.env_name)}
      gcp_project_id                                  = ${jsonencode(local.env_vars.gcp_project_id)}
      kubernetes_cluster_subnet_name                  = ${jsonencode(dependency.vpc.outputs.kubernetes_cluster_subnet_name)}
      kubernetes_control_plane_ipv4_cidr              = ${jsonencode(local.env_vars.kubernetes_control_plane_ipv4_cidr)}
      kubernetes_pods_subnet_secondary_range_name     = ${jsonencode(dependency.vpc.outputs.kubernetes_pods_subnet_secondary_range_name)}
      kubernetes_services_subnet_secondary_range_name = ${jsonencode(dependency.vpc.outputs.kubernetes_services_subnet_secondary_range_name)}
      node_count                                      = ${jsonencode(local.env_vars.node_count)}
      node_machine_type                               = ${jsonencode(local.env_vars.node_machine_type)}
      source                                          = "${find_in_parent_folders("modules")}/kubernetes"
      vpc_name                                        = ${jsonencode(dependency.vpc.outputs.vpc_name)}
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "main.tf"
}

generate "outputs" {
  contents  = <<-EOF
    output "control_plane_endpoint" {
      description = "The URI at which the cluster's control plane can be reached"
      value       = module.kubernetes_cluster.control_plane_endpoint
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "outputs.tf"
}
