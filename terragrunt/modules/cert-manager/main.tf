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

resource "google_service_account" "cert_manager" {
  account_id = "cert-manager"
}

data "google_project" "current" {}

resource "google_project_iam_custom_role" "cert_manager" {
  description = "Kubernetes Cert Manager"
  permissions = [
    "dns.changes.create",
    "dns.changes.get",
    "dns.changes.list",
    "dns.managedZones.list",
    "dns.resourceRecordSets.create",
    "dns.resourceRecordSets.delete",
    "dns.resourceRecordSets.list",
    "dns.resourceRecordSets.update",
  ]
  role_id = "cert_manager"
  title   = "Cert Manager"
}

resource "google_project_iam_member" "cert_manager_gcp_service_account" {
  member  = "serviceAccount:${google_service_account.cert_manager.email}"
  project = data.google_project.current.id
  role    = google_project_iam_custom_role.cert_manager.id
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "kubernetes_service_account" "cert_manager" {
  metadata {
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.cert_manager.email
    }
    name      = "cert-manager"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
}

resource "google_project_iam_member" "cert_manager_k8s_service_account" {
  member  = "serviceAccount:${data.google_project.current.project_id}.svc.id.goog[${kubernetes_service_account.cert_manager.metadata[0].namespace}/${kubernetes_service_account.cert_manager.metadata[0].name}]"
  project = data.google_project.current.id
  role    = "roles/iam.workloadIdentityUser"
}

resource "kubernetes_network_policy" "cert_manager_egress_to_control_plane" {
  metadata {
    name      = "cert-manager-egress-to-control-plane"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  spec {
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      to {
        ip_block {
          cidr = var.kubernetes_control_plane_cidr_ipv4
        }
      }
    }
    pod_selector {}
    policy_types = ["Egress"]
  }
}

resource "kubernetes_network_policy" "cert_manager_ingress_from_control_plane" {
  metadata {
    name      = "cert-manager-ingress-from-control-plane"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }
  spec {
    ingress {
      ports {
        port     = 10250
        protocol = "TCP"
      }
      from {
        ip_block {
          cidr = var.kubernetes_control_plane_cidr_ipv4
        }
      }
    }
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "helm_release" "cert_manager" {
  atomic           = true
  chart            = "cert-manager"
  create_namespace = false
  depends_on = [
    kubernetes_manifest.crds,
    kubernetes_network_policy.cert_manager_egress_to_control_plane,
    kubernetes_network_policy.cert_manager_ingress_from_control_plane,
    kubernetes_service_account.cert_manager,
  ]
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  skip_crds  = true
  values = [
    yamlencode({
      "clusterResourceNamespace" = kubernetes_namespace.cert_manager.metadata[0].name
      "serviceAccount" = {
        "create" = false
        "name"   = kubernetes_service_account.cert_manager.metadata[0].name
      }
    }),
  ]
  version = "v${var.cert_manager_version}"
}

resource "kubernetes_manifest" "test_issuer" {
  depends_on = [helm_release.cert_manager]
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" = "test-issuer"
    }
    "spec" = {
      "acme" = {
        # You must replace this email address with your own.
        # Let's Encrypt will use this to contact you about expiring
        # certificates, and issues related to your account.
        "email" = "cameronhudson8@gmail.com"
        # If the ACME server supports profiles, you can specify the profile name here.
        # See #acme-certificate-profiles below.
        "profile" = "tlsserver"
        "server"  = "https://acme-staging-v02.api.letsencrypt.org/directory"
        "privateKeySecretRef" = {
          # Secret resource that will be used to store the account's private key.
          # This is your identity with your ACME provider. Any secret name may be
          # chosen. It will be populated with data automatically, so generally
          # nothing further needs to be done with the secret. If you lose this
          # identity/secret, you will be able to generate a new one and generate
          # certificates for any/all domains managed using your previous account,
          # but you will be unable to revoke any certificates generated using that
          # previous account.
          "name" = "issuer-account-key"
        }
        # Add a single challenge solver, HTTP01 using nginx
        "solvers" = [{
          "dns01" = {
            "cloudDNS" = {
              "project" = data.google_project.current.project_id
            }
          }
          "selector" = {
            "dnsZones" = var.dns_zones
          }
        }]
      }
    }
  }
}
