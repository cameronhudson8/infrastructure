include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env-vars.hcl")).locals
  global_vars = read_terragrunt_config(find_in_parent_folders("global-vars.hcl")).locals
}

generate "providers" {
  path      = "terragrunt-generated-providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        kubectl = {
          source  = "gavinbunney/kubectl"
          version = "~> 1.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.0"
        }
      }
      required_version = "~> 1.0"
    }

    provider "kubectl" {
      config_path    = "~/.kube/config"
      config_context = ${jsonencode(local.env_vars.kube_context)}
    }

    provider "kubernetes" {
      config_path    = "~/.kube/config"
      config_context = ${jsonencode(local.env_vars.kube_context)}
    }
  EOF
}

generate "module" {
  path      = "terragrunt-generated-module.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    module "prometheus_operator" {
      source           = "../../../modules/prometheus-operator"
      operator_version = ${jsonencode(local.global_vars.prometheus_operator_version)}
    }
  EOF
}
