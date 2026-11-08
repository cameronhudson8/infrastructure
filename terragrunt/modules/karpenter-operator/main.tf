locals {
  # The region containing the cluster, whether the cluster is zonal (e.g. us-central1-a) or regional (e.g. us-central1).
  cluster_region                  = regex("^[a-z]+-[a-z]+[0-9]+", var.cluster_location)
  controller_role                 = yamldecode(data.http.karpenter_controller_role.response_body)
  google_service_account_name     = "karpenter"
  kubernetes_service_account_name = "karpenter"
  namespace                       = "karpenter"
}

resource "google_service_account" "karpenter" {
  account_id   = local.google_service_account_name
  display_name = "Karpenter"
}

data "google_project" "current" {}

data "google_service_account" "nodes" {
  account_id = var.node_service_account_name
}

# The minimal set of permissions required by the Karpenter controller, as published for this version of Karpenter.
data "http" "karpenter_controller_role" {
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Failed to download the Karpenter controller IAM role (HTTP ${self.status_code}) from ${self.url}."
    }
  }
  url = "https://raw.githubusercontent.com/cloudpilot-ai/karpenter-provider-gcp/v${var.karpenter_version}/deploy/iam/karpenter-controller-role.yaml"
}

resource "google_project_iam_custom_role" "karpenter_controller" {
  description = local.controller_role.description
  permissions = local.controller_role.includedPermissions
  project     = data.google_project.current.project_id
  role_id     = "karpenter_controller"
  title       = local.controller_role.title
}

resource "google_project_iam_member" "karpenter" {
  member  = "serviceAccount:${google_service_account.karpenter.email}"
  project = data.google_project.current.project_id
  role    = google_project_iam_custom_role.karpenter_controller.id
}

# Allow the Karpenter controller to attach the node service account (and only that one) to the VMs it creates.
resource "google_service_account_iam_member" "karpenter_act_as_nodes" {
  member             = "serviceAccount:${google_service_account.karpenter.email}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = data.google_service_account.nodes.name
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
    apiVersion = "networking.gke.io/v1alpha1"
    kind       = "FQDNNetworkPolicy"
    metadata = {
      name      = "karpenter"
      namespace = "karpenter"
    }
    spec = {
      egress = [{
        matches = [
          { name = "gcloud-compute.com" },
          { pattern = "*.googleapis.com" },
        ]
        ports = [{
          port     = 443
          protocol = "TCP"
        }]
      }]
      podSelector = {}
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
      controller = {
        settings = {
          # Despite its name, clusterLocation is the region used for instance type discovery.
          clusterLocation               = local.cluster_region
          clusterName                   = var.cluster_name
          defaultNodepoolServiceAccount = data.google_service_account.nodes.email
          # The exact location of the cluster (a zone, for zonal clusters), used for GKE API calls.
          nodeLocation = var.cluster_location
          projectID    = data.google_project.current.project_id
        }
      }
      credentials = {
        enabled = false
      }
      serviceAccount = {
        annotations = {
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
    google_service_account_iam_member.karpenter_act_as_nodes,
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
