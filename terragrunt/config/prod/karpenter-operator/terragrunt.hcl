include "backend" {
  path = "${find_in_parent_folders("_common")}/backend.hcl"
}

include "common" {
  path = "${find_in_parent_folders("_common")}/karpenter-operator/terragrunt.hcl"
}
