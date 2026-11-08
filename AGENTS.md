# AGENTS.md

Guidance for coding agents working in this repository. It describes how the code and configuration should be written. It
deliberately says nothing about what is currently deployed.

## Repository layout

* `terragrunt/modules/<module>/`: Reusable Terraform modules (`main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf`).
* `terragrunt/config/_common/<module>/terragrunt.hcl`: The Terragrunt configuration for each module, shared by all
  environments. It uses `generate` blocks to produce `terraform.tf`, `providers.tf`, `main.tf`, and `outputs.tf`.
* `terragrunt/config/_common/backend.hcl`: The shared GCS backend configuration.
* `terragrunt/config/<env>/<module>/terragrunt.hcl`: Leaf configurations. These must be identical across modules and
  environments; they only include `backend.hcl` and the matching `_common` configuration.
* `terragrunt/config/<env>/env.tfvars`: All per-environment values, including the versions of upstream components.
* `terragrunt/config/global.tfvars`: Values shared by all environments.

Environments must differ only in their `env.tfvars` files. Don't add environment-specific logic anywhere else.

## Commands

```shell
# Authenticate (Terraform uses application-default credentials, not the gcloud CLI's credentials).
gcloud auth application-default login

# Plan or apply a single module in a single environment.
terragrunt plan --working-dir ./terragrunt/config/<env>/<module>
terragrunt apply --working-dir ./terragrunt/config/<env>/<module>

# Run all checks (terraform fmt, tflint, trivy, and general file hygiene). Run this before considering a change done.
pre-commit run --all-files
```

## Style

* Sort key-value pairs by key. This applies to Terraform arguments, object literals, maps, `variable`/`output`
  attributes, Helm values, Kubernetes manifests, and tfvars files. Nested blocks follow the same rule as arguments.
* Sort lists of objects by the object's main identifier (usually `name`, otherwise the most identifying field, such as
  `key` or `id`).
* Sort the elements of other lists too, unless their order is meaningful (for example, ordered rules, command arguments,
  or a priority list).
* Don't quote object keys unless they require it. Use `name = "x"`, not `"name" = "x"`. Keys containing characters such
  as `.` or `/` (for example `"iam.gke.io/gcp-service-account"`) must stay quoted.
* Comments should explain why something is done, not restate what the code does.
* Use the `_v1` (versioned) resources of the `kubernetes` provider, not the deprecated unversioned ones.

## Versions and dependencies

* Constrain providers to a major version with a pessimistic constraint (for example `version = "~> 8.0"`). Keep the
  constraint for a given provider the same in every module's `terraform.tf` and in every `_common` `generate "terraform"`
  block.
* Commit the `.terraform.lock.hcl` files. After changing a provider constraint, regenerate them with
  `terragrunt init -upgrade --working-dir ./terragrunt/config/<env>/<module>`.
* Pin upstream components (Helm charts, operators, etc.) to exact versions in `env.tfvars` and pass them into modules as
  variables. Don't hardcode versions inside modules.
* Don't copy upstream files (such as IAM role definitions or CRDs) into this repository. Download the version matching
  the configured component version at plan time with a `data "http"` source, and add a `postcondition` that checks for
  `status_code == 200`.
* Before upgrading a component across versions, read its changelog or migration guide for every release in between and
  apply any required changes.

## Networking: IPv6-first

This entire project is IPv6-first.

* Design for IPv6 by default. Use dual-stack (`IPV4_IPV6`) only where IPv4 is still required for compatibility.
* Every new resource that supports IPv6 must have it enabled. Firewall rules, network policies, load balancers, and DNS
  records must cover IPv6 traffic, not just IPv4.
* Only build something IPv4-only when the platform offers no IPv6 support for it. Leave a comment explaining that, so
  it can be revisited later.

## Security

* Grant least privilege. Prefer custom IAM roles with only the required permissions over broad predefined roles. Scope
  bindings to specific resources (for example, `roles/iam.serviceAccountUser` on one service account) rather than the
  whole project.
* Clusters use default-deny network policies. Any new workload needs explicit network policies for the ingress and egress
  traffic it requires.

## Architecture

* Apply dependency inversion to long-lived infrastructure. Create resources that should outlive the workloads using them
  (such as load balancers, static IP addresses, and certificates) in Terraform, and pass references to them into the
  workloads' configuration. Replacing a workload must never destroy that infrastructure.
