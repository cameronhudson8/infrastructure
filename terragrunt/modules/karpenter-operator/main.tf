resource "google_service_account" "karpenter" {
  account_id = "karpenter"
}

data "google_project" "current" {}

resource "google_project_iam_member" "karpenter_gcp_service_account" {
  for_each = toset([
    "roles/compute.admin",
    "roles/container.admin",
  ])
  member  = "serviceAccount:${google_service_account.karpenter.email}"
  project = data.google_project.current.id
  role    = each.value
}

# Allow Karpenter to provision Kubernetes nodes that run as a different GCP
# service account (the GKE node service account).
resource "google_service_account_iam_member" "karpenter" {
  member             = "serviceAccount:${google_service_account.karpenter.email}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = var.node_service_account_name
}

data "external" "git_repo" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    <<-BASH
      QUERY=$(cat /dev/stdin)
      
      version=$(jq -er '.version' <<<"$${QUERY}")

      git_clone_dir="/tmp/repos/karpenter"
      if [ -d "$${git_clone_dir}" ]; then
        (
          cd "$${git_clone_dir}"
          git fetch --all --quiet
          git reset \
              --hard "$${version}" \
              --quiet
        )
      else
          mkdir -p "$${git_clone_dir}"
          git clone git@github.com:cloudpilot-ai/karpenter-provider-gcp.git "$${git_clone_dir}" \
              --branch "$${version}" \
              --depth 1 \
              --quiet
      fi
      echo "{\"path\":\"$${git_clone_dir}\"}"
    BASH
  ]
  query = {
    "version" = var.karpenter_version
  }
}

resource "kubernetes_manifest" "crds" {
  for_each = {
    for manifest in [
      for yaml_file in toset(fileset("${data.external.git_repo.result.path}/charts/karpenter/crds", "**/*.y*ml")) :
      yamldecode(file("${data.external.git_repo.result.path}/charts/karpenter/crds/${yaml_file}"))
    ] :
    join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      contains(keys(manifest.metadata), "namespace") ? "namespace=${manifest.metadata.namespace}" : null,
      "name=${manifest.metadata.name}",
    ])) => manifest
  }
  manifest = each.value
}

locals {
  namespace                = "karpenter"
  k8s_service_account_name = "karpenter"
}

resource "google_project_iam_member" "karpenter_k8s_service_account" {
  member  = "serviceAccount:${data.google_project.current.project_id}.svc.id.goog[${local.namespace}/${local.k8s_service_account_name}]"
  project = data.google_project.current.id
  role    = "roles/iam.workloadIdentityUser"
}

resource "helm_release" "karpenter" {
  depends_on = [
    google_project_iam_member.karpenter_k8s_service_account,
    kubernetes_manifest.crds,
  ]
  chart            = "${data.external.karpenter_helm_chart.result.karpenterRepoPath}/charts/karpenter"
  create_namespace = true
  name             = "karpenter"
  namespace        = local.namespace
  skip_crds        = true
  values = [
    yamlencode({
      "controller" = {
        "settings" = {
          "clusterName" = var.cluster_name
          "location"    = var.cluster_location
          "projectID"   = data.google_project.current.project_id
        }
      }
      "credentials" = {
        "enabled" = false
      }
      "serviceAccount" = {
        "annotations" = {
          "iam.gke.io/gcp-service-account" = google_service_account.karpenter.email
        }
        "name" = local.k8s_service_account_name
      }
    }),
  ]
}
