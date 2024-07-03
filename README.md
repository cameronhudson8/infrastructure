# infrastructure
Terraform code for creating local and cloud infrastructure where applications are deployed.

## Local Development
⚠️ Only ARM architecture is supported at this time.
1. Install [Lima](https://github.com/lima-vm/lima).
1. Create a VM based on the lima template in [lima/kubernetes.yaml].
    ```
    limactl create --name kubernetes ./lima.yaml
    limactl start kubernetes
    ```
