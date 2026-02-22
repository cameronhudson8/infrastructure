locals {
  google_service_account_name     = "karpenter"
  kubernetes_service_account_name = "karpenter"
  namespace                       = "karpenter"
}

resource "google_service_account" "karpenter" {
  account_id   = local.google_service_account_name
  display_name = "Karpenter"
}

data "google_project" "current" {}

resource "google_project_iam_member" "karpenter" {
  for_each = toset([
    "roles/compute.admin",
    "roles/container.admin",
  ])
  member  = "serviceAccount:${google_service_account.karpenter.email}"
  project = data.google_project.current.id
  role    = each.value
}

resource "google_service_account_iam_member" "karpenter" {
  member             = "serviceAccount:${data.google_project.current.project_id}.svc.id.goog[${local.namespace}/${local.kubernetes_service_account_name}]"
  role               = "roles/iam.workloadIdentityUser"
  service_account_id = google_service_account.karpenter.name
}

resource "kubernetes_namespace_v1" "karpenter" {
  metadata {
    name = local.namespace
  }
}

data "kubernetes_endpoints_v1" "kubernetes" {
  metadata {
    name      = "kubernetes"
    namespace = "default"
  }
}

resource "kubernetes_network_policy_v1" "karpenter_egress_to_control_plane" {
  metadata {
    name      = "karpenter-egress-to-kubernetes"
    namespace = kubernetes_namespace_v1.karpenter.metadata[0].name
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

resource "kubernetes_network_policy_v1" "karpenter_egress_to_node_metadata" {
  metadata {
    name      = "karpenter-egress-to-node-metadata"
    namespace = kubernetes_namespace_v1.karpenter.metadata[0].name
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

data "helm_template" "karpenter" {
  chart            = "karpenter"
  create_namespace = false
  kube_version     = var.kubernetes_version
  name             = "karpenter"
  namespace        = local.namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  skip_crds        = false
  values = [
    yamlencode({
      "controller" = {
        "settings" = {
          "clusterName"     = var.cluster_name
          "clusterLocation" = var.cluster_location
          "projectID"       = data.google_project.current.project_id
        }
      }
      "credentials" = {
        "enabled" = false
      }
      "serviceAccount" = {
        "annotations" = {
          "iam.gke.io/gcp-service-account" = "${local.google_service_account_name}@${data.google_project.current.project_id}.iam.gserviceaccount.com"
        }
      }
    }),
  ]
  version = "v${var.karpenter_version}"
}

resource "kubernetes_manifest" "karpenter_crds" {
  for_each = {
    for crd in [
      for crd_string in data.helm_template.karpenter.crds : yamldecode(crd_string)
    ] :
    join(",", [
      "apiVersion=${crd.apiVersion}",
      "kind=${crd.kind}",
      "name=${crd.metadata.name}",
    ]) => crd
  }
  manifest = each.value
}

resource "helm_release" "karpenter" {
  atomic           = true
  chart            = data.helm_template.karpenter.chart
  create_namespace = data.helm_template.karpenter.create_namespace
  depends_on = [
    google_project_iam_member.karpenter,
    google_service_account_iam_member.karpenter,
    kubernetes_manifest.fqdn_network_policy_karpenter_egress_to_google_apis,
    kubernetes_manifest.karpenter_crds,
    kubernetes_network_policy_v1.karpenter_egress_to_control_plane,
    kubernetes_network_policy_v1.karpenter_egress_to_node_metadata,
  ]
  name       = data.helm_template.karpenter.name
  namespace  = data.helm_template.karpenter.namespace
  repository = data.helm_template.karpenter.repository
  skip_crds  = true
  values     = data.helm_template.karpenter.values
}
