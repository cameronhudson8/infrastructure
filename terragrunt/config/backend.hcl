remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_env("HOME")}/.terraform-state/cameronhudson8/infrastructure/local/${basename(get_terragrunt_dir())}.json"
  }
}
