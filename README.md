# infrastructure

Terraform code for creating local and cloud infrastructure where applications are deployed.

## Architecture

![architecture](./docs/architecture.drawio.svg)

## Prerequisites

* [terraform](https://developer.hashicorp.com/terraform/install)
* [terragrunt](https://terragrunt.gruntwork.io/docs/getting-started/install/)

## Setup

1. To use this repo, an existing Google Cloud Storage (GCS) buckets needed. You can create such a bucket with the following commands.
    ```
    ENV_NAME="staging"
    gcloud storage buckets create "gs://cameronhudson8-${ENV_NAME}-tf-state" \
        --location 'us-west4' \
        --project 'cameronhudson8' \
        --public-access-prevention
    gcloud storage buckets update "gs://cameronhudson8-${ENV_NAME}-tf-state" \
        --project 'cameronhudson8' \
        --versioning
    ```

## Usage

Apply the Terraform modules in the following order.

```
terragrunt apply --working-dir ./terragrunt/<module>
```
Modules:
1. `vpc`
1. `cluster`
1. In-cluster services
    * (TODO) `vpn`
    * `ingress-nginx`
    * (TODO) `ci-cd`
    * (TODO) `identity`
    * (TODO) `secrets`
    * Observability
        1. `monitoring-crds`
        1. `monitoring`

## Cleanup

1. Destroy the Terraform the the opposite order listed above.
1. Destroy the Google GCS bucket used to store the Terraform state.
    ```
    ENV_NAME="staging"
    gcloud storage buckets delete "gs://cameronhudson8-${ENV_NAME}-tf-state" \
        --project 'cameronhudson8'
    ```
