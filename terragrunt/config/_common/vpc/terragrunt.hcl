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
    module "vpc" {
      gcp_region                    = "${local.env_vars.gcp_region}"
      kubernetes_nodes_ipv4_cidr    = ${jsonencode(local.env_vars.kubernetes_nodes_ipv4_cidr)}
      kubernetes_pods_ipv4_cidr     = ${jsonencode(local.env_vars.kubernetes_pods_ipv4_cidr)}
      kubernetes_services_ipv4_cidr = ${jsonencode(local.env_vars.kubernetes_services_ipv4_cidr)}
      load_balancers_ipv4_cidr      = ${jsonencode(local.env_vars.load_balancers_ipv4_cidr)}
      source                        = "${find_in_parent_folders("modules")}/vpc"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "main.tf"
}

generate "outputs" {
  contents  = <<-EOF
    output "kubernetes_cluster_subnet_name" {
      description = "The name of the subnet to use for the Kubernetes cluster (Nodes, Pods, and Services)"
      value       = module.vpc.kubernetes_cluster_subnet_name
    }

    output "kubernetes_pods_subnet_secondary_range_name" {
      description = "The name of the secondary range of the Kubernetes cluster subnet to use for the Pod IPs"
      value       = module.vpc.kubernetes_pods_subnet_secondary_range_name
    }

    output "kubernetes_services_subnet_secondary_range_name" {
      description = "The name of the secondary range of the Kubernetes cluster subnet to use for the Service IPs"
      value       = module.vpc.kubernetes_services_subnet_secondary_range_name
    }

    output "vpc_name" {
      description = "The name of the VPC"
      value       = module.vpc.vpc_name
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "outputs.tf"
}
