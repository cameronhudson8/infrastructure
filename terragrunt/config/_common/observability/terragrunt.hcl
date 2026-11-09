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
          version = "~> 8.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 3.0"
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
    module "observability" {
      email_recipient_email_address        = ${jsonencode(local.global_vars.observability.email_recipient_email_address)}
      email_sender_email_address           = "${get_env("EMAIL_SENDER_EMAIL_ADDRESS")}"
      email_sender_password                = "${get_env("EMAIL_SENDER_PASSWORD")}"
      email_sender_transport               = ${jsonencode(local.global_vars.observability.email_sender_transport)}
      env_name                             = ${jsonencode(local.env_vars.env_name)}
      fluentd_version                      = ${jsonencode(local.env_vars.observability.fluentd_version)}
      grafana_helm_chart_version           = ${jsonencode(local.env_vars.observability.grafana_helm_chart_version)}
      kube_prometheus_version              = ${jsonencode(local.env_vars.observability.kube_prometheus_version)}
      kubernetes_version                   = ${jsonencode(local.env_vars.kubernetes_version)}
      loki_helm_chart_version              = ${jsonencode(local.env_vars.observability.loki_helm_chart_version)}
      mimir_distributed_helm_chart_version = ${jsonencode(local.env_vars.observability.mimir_distributed_helm_chart_version)}
      source                               = "${find_in_parent_folders("modules")}/observability"
      tempo_distributed_helm_chart_version = ${jsonencode(local.env_vars.observability.tempo_distributed_helm_chart_version)}
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "main.tf"
}
