dependencies {
  paths = [
    "../cluster",
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
        external = {
          source  = "hashicorp/external"
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
    provider "kubernetes" {
      config_path    = "~/.kube/config"
      config_context = ${jsonencode(local.env_vars.kubectl_context_name)}
    }

    data "external" "kubernetes" {
      program = [
        "/usr/bin/env",
        "bash",
        "-eu",
        "-o",
        "pipefail",
        "-c",
        <<-SCRIPT
            yq \
                '
                    .
                    | (.contexts[] | select(.name == "${local.env_vars.kubectl_context_name}") | .context.cluster) as $clusterName
                    | (.clusters[] | select(.name == $clusterName) | .cluster["certificate-authority-data"] | @base64d) as $certificateAuthority
                    | (.clusters[] | select(.name == $clusterName) | .cluster.server) as $server
                    | (.contexts[] | select(.name == "${local.env_vars.kubectl_context_name}") | .context.user) as $userName
                    | (.users[] | select(.name == $userName) | .user["client-certificate-data"] | @base64d) as $clientCertificate
                    | (.users[] | select(.name == $userName) | .user["client-key-data"] | @base64d) as $clientKey
                    |
                        {
                            "client_certificate": $clientCertificate,
                            "client_key": $clientKey,
                            "cluster_ca_certificate": $certificateAuthority,
                            "server": $server
                        }
                ' \
                ~/.kube/config \
                --exit-status \
                --indent=0 \
                --no-colors \
                --output-format=json \
                --unwrapScalar
        SCRIPT
      ]
    }
  EOF
}

generate "main" {
  path      = "${get_terragrunt_dir()}/main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    module "vpa_crds" {
      kubernetes_client_certificate     = "$${data.external.kubernetes.result.client_certificate}"
      kubernetes_client_key             = "$${data.external.kubernetes.result.client_key}"
      kubernetes_cluster_ca_certificate = "$${data.external.kubernetes.result.cluster_ca_certificate}"
      kubernetes_server                 = "$${data.external.kubernetes.result.server}"
      namespace_name                    = ${jsonencode(local.global_vars.vpa_namespace_name)}
      operator_version                  = ${jsonencode(local.env_vars.vpa_operator_version)}
      source                            = "../../../modules/vpa-crds"
    }
  EOF
}
