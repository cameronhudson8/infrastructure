# infrastructure

Terraform code for creating local and cloud infrastructure where applications are deployed.

## Prerequisites

* [kubectl](https://kubernetes.io/docs/tasks/tools/)
* [lima](https://github.com/lima-vm/lima)
* [terraform](https://developer.hashicorp.com/terraform/install)
* [terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)
* [yq](https://mikefarah.gitbook.io/yq)
* A mail server configured with a domain. The email address used for Prometheus monitoring is set in [terragrunt/config/globals.hcl].

## Usage

### Local Development

> [!IMPORTANT]
> Only ARM architecture is supported at this time.

1. Create a local virtual machine (VM) for Kubernetes.
    ```
    K8S_VERSION='1.30'
    VM_NAME='k8s'
    limactl create https://raw.githubusercontent.com/lima-vm/lima/v0.22.0/examples/k8s.yaml \
        --cpus 2 \
        --disk 20GiB \
        --memory 4GiB \
        --name "${VM_NAME}" \
        --set ".provision = (.provision | map(to_entries | map({ \"key\": .key, \"value\": (.value | sub(\"VERSION=.*\"; \"VERSION=${K8S_VERSION}\")) }) | from_entries))"
1. Start the VM.
    ```
    limactl start "${VM_NAME}"
    ```
1. Import the Kubernetes context from the VM.
    ```
    KUBE_CONTEXT='local'
    yq -i ". *= load(\"${HOME}/.lima/${VM_NAME}/copied-from-guest/kubeconfig.yaml\") | .contexts[0].name = \"${KUBE_CONTEXT}\"" ~/.kube/config
    ```
1. Confirm that you can list the namespaces in the cluster.
    ```
    kubectl --context "${KUBE_CONTEXT}" get namespaces
    ```
1. Check the Kubernetes cluster version and your kubectl version. If the difference between the two is too large, then [install a newer version of kubectl](https://kubernetes.io/docs/tasks/tools/).
    ```
    kubectl --context "${KUBE_CONTEXT}" version
    ```
1. If you used a different value for `KUBE_CONTEXT`, then update the value of `kube_context` in `./terragrunt/config/local/env-vars`.hcl.
1. Apply the modules.
    ```
    ENV_NAME='local'
    export MONITORING_EMAILS_SENDER_EMAIL_ADDRESS='...'
    export MONITORING_EMAILS_SENDER_PASSWORD='...'
    modules=(
      "monitoring-crds",
      "vpa-crds",
      "monitoring"
    )
    for module in "${modules[@]}"; do
        terragrunt apply --terragrunt-working-dir "./terragrunt/config/${ENV_NAME}/${module}"
    done
    ```

## Cleanup

### Local Development

1. Destroy the modules in opposite order in which they were applied.
    ```
    ENV_NAME='local'
    export MONITORING_EMAILS_SENDER_EMAIL_ADDRESS='...'
    export MONITORING_EMAILS_SENDER_PASSWORD='...'
    modules=(
      "monitoring",
      "vpa-crds",
      "monitoring-crds"
    )
    for module in "${modules[@]}"; do
        terragrunt destroy --terragrunt-working-dir "./terragrunt/config/${ENV_NAME}/${module}"
    done
1. Delete the Kubernetes context.
    ```
    KUBE_CONTEXT='local'
    kubectl config delete-context "${KUBE_CONTEXT}"
    ```
1. Delete the Kubernetes VM.
    ```
    VM_NAME='k8s'
    limactl stop "${VM_NAME}"
    limactl delete "${VM_NAME}"
    ```
