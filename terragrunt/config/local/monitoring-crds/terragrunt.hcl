include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env-vars.hcl")).locals
  global_vars = read_terragrunt_config(find_in_parent_folders("global-vars.hcl")).locals
}

generate "versions" {
  path      = "${get_terragrunt_dir()}/versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.0"
        }
      }
      required_version = "~> 1.0"
    }
  EOF
}

generate "providers" {
  path      = "${get_terragrunt_dir()}/providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      config_path    = "~/.kube/config"
      config_context = ${jsonencode(local.env_vars.kube_context)}
    }
  EOF
}

generate "main" {
  path      = "${get_terragrunt_dir()}/main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    module "monitoring_crds" {
      alertmanager_replicas             = ${jsonencode(local.env_vars.alertmanager_replicas)}
      email_recipient_address           = ${jsonencode(local.global_vars.monitoring_email_recipient_address)}
      kube_prometheus_alerts_to_disable = ${jsonencode(local.env_vars.kube_prometheus_alerts_to_disable)}
      kube_prometheus_version           = ${jsonencode(local.global_vars.kube_prometheus_version)}
      kube_state_metrics_version        = ${jsonencode(local.global_vars.kube_state_metrics_version)}
      namespace_name                    = ${jsonencode(local.global_vars.monitoring_namespace_name)}
      prometheus_replicas               = ${jsonencode(local.env_vars.prometheus_replicas)}
      source                            = "../../../modules/monitoring-crds"
    }
  EOF
}
