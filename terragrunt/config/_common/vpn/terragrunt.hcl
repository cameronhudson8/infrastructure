dependency "kubernetes_cluster" {
  config_path = find_in_parent_folders("kubernetes-cluster")
}

dependency "vpc" {
  config_path = find_in_parent_folders("vpc")
}

locals {
  env_vars    = jsondecode(read_tfvars_file(find_in_parent_folders("env.tfvars")))
  global_vars = jsondecode(read_tfvars_file(find_in_parent_folders("global.tfvars")))
}

generate "terraform" {
  contents  = <<-EOF
    terraform {
      required_providers {
        external = {
          source  = "hashicorp/external"
          version = "~> 2.0"
        }
        google = {
          source  = "hashicorp/google"
          version = "~> 6.0"
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
    module "vpn" {
      kubernetes_cluster_id                  = ${jsonencode(dependency.kubernetes_cluster.outputs.kubernetes_cluster_id)}
      kubernetes_nodes_service_account_email = ${jsonencode(dependency.kubernetes_cluster.outputs.kubernetes_nodes_service_account_email)}
      node_pool_vpn_machine_type             = ${jsonencode(local.env_vars.node_pool_vpn_machine_type)}
      node_pool_vpn_node_count               = ${jsonencode(local.env_vars.node_pool_vpn_node_count)}
      # private_subnet_id                      = ${jsonencode(dependency.vpc.outputs.private_subnet_id)}
      private_subnet_ipv6_cidr               = ${jsonencode(dependency.vpc.outputs.private_subnet_ipv6_cidr)}
      source                                 = "${find_in_parent_folders("modules")}/vpn"
      # vpc_id                                 = ${jsonencode(dependency.vpc.outputs.vpc_id)}
      vpn_clients_ipv6_prefix_length         = ${jsonencode(local.env_vars.vpn_clients_ipv6_prefix_length)}
      wireguard_version                      = ${jsonencode(local.env_vars.wireguard_version)}
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
