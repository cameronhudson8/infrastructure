dependencies {
  paths = [
    "../monitoring-crds",
  ]
}

include "backend" {
  path = find_in_parent_folders("backend.hcl")
}

locals {
  env_vars    = jsondecode(read_tfvars_file(find_in_parent_folders("env.tfvars")))
  global_vars = jsondecode(read_tfvars_file(find_in_parent_folders("global.tfvars")))
}

generate "terraform" {
  path      = "${get_terragrunt_dir()}/terraform.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        helm = {
          source  = "hashicorp/helm"
          version = "~> 2.0"
        }
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
    provider "helm" {
      kubernetes {
        config_path    = "~/.kube/config"
        config_context = ${jsonencode(local.env_vars.kubectl_context_name)}
      }
    }

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
      email_recipient_email_address        = ${jsonencode(local.global_vars.monitoring_email_recipient_email_address)}
      email_sender_email_address           = "${get_env("MONITORING_EMAIL_SENDER_EMAIL_ADDRESS")}"
      email_sender_password                = "${get_env("MONITORING_EMAIL_SENDER_PASSWORD")}"
      email_sender_transport               = ${jsonencode(local.global_vars.monitoring_email_sender_transport)}
      env_name                             = ${jsonencode(local.env_vars.env_name)}
      fluentd_version                      = ${jsonencode(local.env_vars.fluentd_version)}
      grafana_helm_chart_version           = ${jsonencode(local.env_vars.grafana_helm_chart_version)}
      kube_prometheus_version              = ${jsonencode(local.env_vars.kube_prometheus_version)}
      loki_distributed_helm_chart_version  = ${jsonencode(local.env_vars.loki_distributed_helm_chart_version)}
      mimir_distributed_helm_chart_version = ${jsonencode(local.env_vars.mimir_distributed_helm_chart_version)}
      mimir_ingester_replicas              = ${jsonencode(local.env_vars.mimir_ingester_replicas)}
      mimir_querier_replicas               = ${jsonencode(local.env_vars.mimir_querier_replicas)}
      mimir_query_scheduler_replicas       = ${jsonencode(local.env_vars.mimir_query_scheduler_replicas)}
      mimir_zone_aware_replication         = ${jsonencode(local.env_vars.mimir_zone_aware_replication)}
      namespace_name                       = ${jsonencode(local.global_vars.monitoring_namespace_name)}
      source                               = "../../../modules/monitoring"
      storage_class_name                   = ${jsonencode(local.env_vars.storage_class_name)}
      tempo_distributed_helm_chart_version = ${jsonencode(local.env_vars.tempo_distributed_helm_chart_version)}
      tempo_ingester_replicas              = ${jsonencode(local.env_vars.tempo_ingester_replicas)}
      vm_name                              = ${jsonencode(local.env_vars.vm_name)}
    }
  EOF
}
