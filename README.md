# infrastructure

Terraform code for creating local and cloud infrastructure where applications are deployed.

## Planned Architecture

![architecture](./docs/architecture.drawio.svg)

## Prerequisites

* [terraform](https://developer.hashicorp.com/terraform/install)
* [terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)

## Usage

Apply the Terragrunt modules in the following order.

```
terragrunt apply --working-dir ./terragrunt/<module>
```
Modules:
1. `vpc`
1. (TBD) `cluster`
1. In-cluster services
    * (TBD) `vpn`
    * `ingress-nginx`
    * (TBD) `ci-cd`
    * (TBD) `identity`
    * (TBD) `secrets`
    * Observability
        1. `monitoring-crds`
        1. `monitoring`
