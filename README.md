# infrastructure

Terraform code for creating local and cloud infrastructure where applications are deployed.

## Prerequisites

* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [lima](https://github.com/lima-vm/lima)
* [terraform](https://developer.hashicorp.com/terraform/install)
* [terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)
* [yq](https://mikefarah.gitbook.io/yq)
* A mail server configured with a domain. The email address used for Prometheus monitoring is set in [terragrunt/config/global-vars.hcl].

## Usage

### Local Development

1. Apply the modules.
    ```
    ENV_NAME='local'
    export MONITORING_EMAIL_SENDER_EMAIL_ADDRESS='...'
    export MONITORING_EMAIL_SENDER_PASSWORD='...'
    modules=(
      "cluster",
      "monitoring-crds",
      "vpa-crds",
      "monitoring"
    )
    for module in "${modules[@]}"; do
        terragrunt apply --terragrunt-working-dir "./terragrunt/config/${ENV_NAME}/${module}"
    done
    ```
1. Check the Kubernetes cluster version and your kubectl version. If the difference between the two is too large, then [install a newer version of kubectl](https://kubernetes.io/docs/tasks/tools/).
    ```
    kubectl --context local version
    ```

## Cleanup

### Local Development

1. Destroy the modules in opposite order in which they were applied.
    ```
    ENV_NAME='local'
    export MONITORING_EMAIL_SENDER_EMAIL_ADDRESS='...'
    export MONITORING_EMAIL_SENDER_PASSWORD='...'
    modules=(
      "monitoring",
      "vpa-crds",
      "monitoring-crds",
      "cluster"
    )
    for module in "${modules[@]}"; do
        terragrunt destroy --terragrunt-working-dir "./terragrunt/config/${ENV_NAME}/${module}"
    done
