local {
  env_vars    = jsondecode(read_tfvars_file(find_in_parent_folders("env.tfvars")))
  global_vars = jsondecode(read_tfvars_file(find_in_parent_folders("global.tfvars")))
}

generate "backend" {
  contents = <<-EOF
    backend "gcs" {
        bucket  = "${env_vars.tf_state_bucket_name}"
        prefix  = "repositories/infrastructure/modules/${basename(get_original_terragrunt_dir())}"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "backend.tf"
}

generate "terraform" {
  contents = <<-EOF
    terraform {
      required_providers {
        google = {
          source  = "hashicorp/google"
          version = "~> 6.0"
        }
      }
      required_version = "~> 1.0"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "terraform.tf"
}

generate "providers" {
  contents = <<-EOF
    provider "google" {
      project = "${local.env_vars.gcp_project_id}"
      region  = "${local.env_vars.gcp_region}"
    }
  EOF
  if_exists = "overwrite_terragrunt"
  path      = "providers.tf"
}
