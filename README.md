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
1. Identify the host port in use by ingress-nginx by examining the ingress-nginx service. In the example below, host port 32318 is mapped to port 80 of the Kubernetes virtual machine.
    ```
    $ kubectl --context local -n ingress-nginx get svc
    NAME                                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
    ingress-nginx-controller             NodePort    10.103.124.199   <none>        80:32318/TCP,443:30877/TCP   26m
    ingress-nginx-controller-admission   ClusterIP   10.100.165.213   <none>        443/TCP                      26m

    $ curl http://localhost:32318
    <html>
    <head><title>404 Not Found</title></head>
    <body>
    <center><h1>404 Not Found</h1></center>
    <hr><center>nginx</center>
    </body>
    </html>
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
