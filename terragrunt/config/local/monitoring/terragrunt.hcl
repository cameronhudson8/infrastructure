dependencies {
  paths = [
    "../monitoring-crds",
  ]
}

include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env-vars.hcl")).locals
  global_vars = read_terragrunt_config(find_in_parent_folders("global-vars.hcl")).locals
}

generate "terraform" {
  path      = "${get_terragrunt_dir()}/terraform.tf"
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
      config_context = ${jsonencode(local.env_vars.kubectl_context_name)}
    }
  EOF
}

generate "main" {
  path      = "${get_terragrunt_dir()}/main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    module "monitoring" {
      email_recipient_email_address = ${jsonencode(local.global_vars.monitoring_email_recipient_email_address)}
      email_sender_email_address    = "${get_env("MONITORING_EMAIL_SENDER_EMAIL_ADDRESS")}"
      email_sender_password         = "${get_env("MONITORING_EMAIL_SENDER_PASSWORD")}"
      email_sender_transport        = ${jsonencode(local.global_vars.monitoring_email_sender_transport)}
      kube_prometheus_version       = ${jsonencode(local.global_vars.kube_prometheus_version)}
      namespace_name                = ${jsonencode(local.global_vars.monitoring_namespace_name)}
      source                        = "../../../modules/monitoring"
    }
  EOF
}
