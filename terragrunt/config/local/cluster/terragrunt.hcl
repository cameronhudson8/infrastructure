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
      required_version = "~> 1.0"
    }
  EOF
}

generate "providers" {
  path      = "${get_terragrunt_dir()}/providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
  EOF
}

generate "main" {
  path      = "${get_terragrunt_dir()}/main.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    module "cluster" {
      kubectl_context_name  = ${jsonencode(local.env_vars.kubectl_context_name)}
      kubernetes_version    = ${jsonencode(local.env_vars.kubernetes_version)}
      lima_version          = ${jsonencode(local.env_vars.lima_version)}
      source                = "../../../modules/cluster-lima"
      vm_name               = ${jsonencode(local.env_vars.vm_name)}
    }
  EOF
}
