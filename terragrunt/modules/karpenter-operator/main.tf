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
  program = ["${path.module}/../../scripts/check-out-git-repo.sh"]
  query = {
    "ref"     = var.karpenter_version
    "repoUri" = "git@github.com:cert-manager/cert-manager.git"
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

resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
  }
}

resource "kubernetes_service_account" "karpenter" {
  metadata {
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.karpenter.email
    }
    name      = "karpenter"
    namespace = kubernetes_namespace.karpenter.metadata[0].name
  }
}

resource "google_project_iam_member" "karpenter_k8s_service_account" {
  member  = "serviceAccount:${data.google_project.current.project_id}.svc.id.goog[${kubernetes_service_account.karpenter.metadata[0].namespace}/${kubernetes_service_account.karpenter.metadata[0].name}]"
  project = data.google_project.current.id
  role    = "roles/iam.workloadIdentityUser"
}

data "kubernetes_endpoints_v1" "kubernetes" {
  metadata {
    name      = "kubernetes"
    namespace = "default"
  }
}

resource "kubernetes_network_policy" "karpenter_egress_to_control_plane" {
  metadata {
    name      = "karpenter-egress-to-kubernetes"
    namespace = kubernetes_namespace.karpenter.metadata[0].name
  }
  spec {
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      to {
        dynamic "ip_block" {
          for_each = flatten([
            for subset in data.kubernetes_endpoints_v1.kubernetes.subset : [
              for address in subset.address : address.ip
            ]
          ])
          content {
            cidr = "${ip_block.value}/32"
          }
        }
      }
    }
    egress {
      ports {
        port     = 80
        protocol = "TCP"
      }
      to {
        ip_block {
          cidr = "169.254.169.254/32"
        }
      }
    }
    pod_selector {}
    policy_types = ["Egress"]
  }
}

resource "kubernetes_network_policy" "karpenter_egress_to_node_metadata" {
  metadata {
    name      = "karpenter-egress-to-node-metadata"
    namespace = kubernetes_namespace.karpenter.metadata[0].name
  }
  spec {
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      to {
        dynamic "ip_block" {
          for_each = flatten([
            for subset in data.kubernetes_endpoints_v1.kubernetes.subset : [
              for address in subset.address : address.ip
            ]
          ])
          content {
            cidr = "${ip_block.value}/32"
          }
        }
      }
    }
    egress {
      ports {
        port     = 80
        protocol = "TCP"
      }
      to {
        ip_block {
          cidr = "169.254.169.254/32"
        }
      }
    }
    pod_selector {}
    policy_types = ["Egress"]
  }
}

resource "kubernetes_manifest" "fqdn_network_policy_karpenter_egress_to_google_apis" {
  manifest = {
    "apiVersion" = "networking.gke.io/v1alpha1"
    "kind"       = "FQDNNetworkPolicy"
    "metadata" = {
      "name"      = "karpenter"
      "namespace" = "karpenter"
    }
    "spec" = {
      "egress" = [{
        "matches" = [
          { "name" = "gcloud-compute.com" },
          { "pattern" = "*.googleapis.com" },
        ]
        "ports" = [{
          "port"     = 443
          "protocol" = "TCP"
        }]
      }]
      "podSelector" = {}

    }
  }
}

resource "helm_release" "karpenter" {
  atomic           = true
  chart            = "${data.external.git_repo.result.path}/charts/karpenter"
  create_namespace = false
  depends_on = [
    google_project_iam_member.karpenter_k8s_service_account,
    kubernetes_manifest.crds,
    kubernetes_manifest.fqdn_network_policy_karpenter_egress_to_google_apis,
    kubernetes_network_policy.karpenter_egress_to_control_plane,
    kubernetes_network_policy.karpenter_egress_to_node_metadata,
    kubernetes_service_account.karpenter,
  ]
  name      = "karpenter"
  namespace = kubernetes_namespace.karpenter.metadata[0].name
  skip_crds = true
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
        "create" = false
        "name"   = kubernetes_service_account.karpenter.metadata[0].name
      }
    }),
  ]
}
