locals {
  env_vars = jsondecode(read_tfvars_file(find_in_parent_folders("env.tfvars")))
}

generate "backend" {
  contents  = <<-EOF
    terraform {
      backend "gcs" {
        bucket  = "${local.env_vars.tf_state_bucket_name}"
        prefix  = "repositories/infrastructure/modules/${basename(get_original_terragrunt_dir())}"
      }
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "backend.tf"
}
