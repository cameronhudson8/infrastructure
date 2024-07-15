# infrastructure

Terraform code for creating local and cloud infrastructure where applications are deployed.

## Setup

### Local Development

> [!IMPORTANT]
> Only ARM architecture is supported at this time.

1. Install [Lima](https://github.com/lima-vm/lima).
1. Create a virtual machine (VM) based on the lima template in [lima/kubernetes.yaml].
    ```
    K8S_VERSION='1.30'
    VM_NAME='k8s'

    limactl create https://raw.githubusercontent.com/lima-vm/lima/v0.22.0/examples/k8s.yaml \
        --arch aarch64 \
        --cpus 2 \
        --disk 20 \
        --memory 4 \
        --name "${VM_NAME}" \
        --network vzNAT \
        --set ".provision = (.provision | map(to_entries | map({ \"key\": .key, \"value\": (.value | sub(\"VERSION=.*\"; \"VERSION=${K8S_VERSION}\")) }) | from_entries))" \
        --tty=false \
        --vm-type vz
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

## Cleanup

### Local Development

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
