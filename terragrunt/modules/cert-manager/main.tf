data "http" "crds" {
  url = "https://github.com/cert-manager/cert-manager/releases/download/v${var.cert_manager_version}/cert-manager.crds.yaml"
}
locals {
  # Multidocument yaml file regex
  document_regex = "(?s)(.*?)(?:(?:\\n|^)---\\s*(?:\\n|\\z)|\\z)"
}
resource "kubernetes_manifest" "crds" {
  for_each = {
    for manifest in [
      for yaml_document in compact(flatten(regexall(local.document_regex, data.http.crds.response_body))) :
      yamldecode(yaml_document)
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


data "kubernetes_endpoints_v1" "kubernetes" {
  metadata {
    name      = "kubernetes"
    namespace = "default"
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "kubernetes_network_policy" "cert_manager_egress_to_control_plane" {
  metadata {
    name      = "cert-manager-egress-to-kubernetes"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
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
    pod_selector {}
    policy_types = ["Egress"]
  }
}

resource "helm_release" "cert_manager" {
  atomic           = true
  chart            = "cert-manager"
  create_namespace = false
  depends_on = [
    kubernetes_manifest.crds,
    kubernetes_network_policy.cert_manager_egress_to_control_plane,
  ]
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  skip_crds  = true
  # values = [
  #   yamlencode({
  #     "controller" = {
  #       "settings" = {
  #         "clusterName" = var.cluster_name
  #         "location"    = var.cluster_location
  #         "projectID"   = data.google_project.current.project_id
  #       }
  #     }
  #     "credentials" = {
  #       "enabled" = false
  #     }
  #     "serviceAccount" = {
  #       "annotations" = {
  #         "iam.gke.io/gcp-service-account" = google_service_account.karpenter.email
  #       }
  #       "name" = local.k8s_service_account_name
  #     }
  #   }),
  # ]
  version = "v${var.cert_manager_version}"
}
