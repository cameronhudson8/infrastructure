resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_network_policy" "deny_ingress_and_egress" {
  metadata {
    name      = "deny-ingress-and-egress"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = [
      "Egress",
      "Ingress",
    ]
  }
}

# Based on https://github.com/prometheus-operator/prometheus-operator/blob/v0.75.1/Documentation/user-guides/getting-started.md
resource "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_secret" "prometheus_service_account_token" {
  metadata {
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.prometheus.metadata[0].name
    }
    name      = "prometheus-service-account"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_cluster_role" "prometheus" {
  metadata {
    name = "prometheus"
  }
  rule {
    api_groups = [
      "",
    ]
    resources = [
      "endpoints",
      "nodes",
      "nodes/metrics",
      "pods",
      "services",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "",
    ]
    resources = [
      "configmaps",
    ]
    verbs = [
      "get",
    ]
  }
  rule {
    api_groups = [
      "networking.k8s.io",
    ]
    resources = [
      "ingresses",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    non_resource_urls = [
      "/metrics",
    ]
    verbs = [
      "get",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "prometheus" {
  metadata {
    name = "prometheus"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "prometheus"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.prometheus.metadata[0].name
    namespace = kubernetes_service_account.prometheus.metadata[0].namespace
  }
}

resource "kubernetes_network_policy" "allow_alertmanager_ingress_from_prometheus" {
  metadata {
    name      = "allow-alertmanager-ingress-from-prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace.monitoring.metadata[0].name
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = kubernetes_manifest.prometheus.manifest.metadata.name
          }
        }
      }
      ports {
        port     = 9093
        protocol = "TCP"
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "alertmanager"
      }
    }
    policy_types = [
      "Ingress",
    ]
  }
}

resource "kubernetes_network_policy" "allow_prometheus_egress_to_alertmanager" {
  metadata {
    name      = "allow-prometheus-egress-to-alertmanager"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace.monitoring.metadata[0].name
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "alertmanager"
          }
        }
      }
      ports {
        port     = 9093
        protocol = "TCP"
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = kubernetes_manifest.prometheus.manifest.metadata.name
      }
    }
    policy_types = [
      "Egress",
    ]
  }
}

resource "kubernetes_secret" "monitoring_emails_from_credentials" {
  metadata {
    name      = "monitoring-emails-from-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    password = var.monitoring_emails_from_auth_password
    username = var.monitoring_emails_from.auth_username
  }
}

resource "kubernetes_manifest" "alertmanager_config" {
  depends_on = [
    kubernetes_secret.monitoring_emails_from_credentials
  ]
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      labels = {
        name = "alertmanager-config"
      }
      name      = "main"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      receivers = [
        {
          emailConfigs = [
            {
              authPassword = {
                name = kubernetes_secret.monitoring_emails_from_credentials.metadata[0].name
                key  = "password"
              }
              authUsername = var.monitoring_emails_from.auth_username
              headers = [
                {
                  key   = "subject"
                  value = "Prometheus Alert"
                }
              ]
              from         = var.monitoring_emails_from.address
              sendResolved = true
              smarthost    = var.monitoring_emails_from.transport
              to           = var.monitoring_emails_to_address
            }
          ]
          name = "email"
        }
      ]
      route = {
        groupBy = [
          "job",
        ]
        receiver = "email"
      }
    }
  }
}

resource "kubernetes_manifest" "alertmanager" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "Alertmanager"
    metadata = {
      name      = "alertmanager"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      alertmanagerConfigSelector = {
        matchLabels = {
          name = "alertmanager-config"
        }
      }
      alertmanagerConfiguration = {
        name = "main"
      }
      replicas = var.alertmanager_replicas
    }
  }
}

# Since kube-state-metrics is yaml-based and has ClusterRoleBinding(s),
# there is no elegant way to specify the namespace.
# By default, it will use namespace 'kube-system'.
data "kubernetes_namespace" "kube_state_metrics" {
  metadata {
    name = "kube-system"
  }
}

resource "kubernetes_network_policy" "allow_kube_state_metrics_ingress_from_prometheus" {
  metadata {
    name      = "allow-kube-state-metrics-ingress-from-prometheus"
    namespace = data.kubernetes_namespace.kube_state_metrics.metadata[0].name
  }
  spec {
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace.monitoring.metadata[0].name
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = kubernetes_manifest.prometheus.manifest.metadata.name
          }
        }
      }
      ports {
        port     = 8080
        protocol = "TCP"
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "kube-state-metrics"
      }
    }
    policy_types = [
      "Ingress",
    ]
  }
}

resource "kubernetes_network_policy" "allow_prometheus_egress_to_kube_state_metrics" {
  metadata {
    name      = "allow-prometheus-egress-to-kube-state-metrics"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = data.kubernetes_namespace.kube_state_metrics.metadata[0].name
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "kube-state-metrics"
          }
        }
      }
      ports {
        port     = 8080
        protocol = "TCP"
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = kubernetes_manifest.prometheus.manifest.metadata.name
      }
    }
    policy_types = [
      "Egress",
    ]
  }
}

resource "kubernetes_manifest" "kube_state_metrics_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "kube-state-metrics"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      endpoints = [
        {
          port = "http-metrics"
        },
      ]
      namespaceSelector = {
        matchNames = [
          data.kubernetes_namespace.kube_state_metrics.metadata[0].name
        ]
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "kube-state-metrics"
        }
      }
    }
  }
}

data "external" "kube_state_metrics" {
  program = [
    "/bin/bash",
    "-c",
    <<-EOF
        download_dir="$(mktemp -d)"
        curl https://github.com/kubernetes/kube-state-metrics/archive/refs/tags/${var.kube_state_metrics_version}.tar.gz \
            --fail-with-body \
            -o "$${download_dir}/kube-state-metrics.tar.gz" \
            -sSL
        mkdir -p "$${download_dir}/kube-state-metrics"
        tar \
            -C "$${download_dir}/kube-state-metrics" \
            -f "$${download_dir}/kube-state-metrics.tar.gz" \
            --strip-components 1 \
            -x
        rm "$${download_dir}/kube-state-metrics.tar.gz"
        echo "{ \"manifests_dir\": \"$${download_dir}/kube-state-metrics\" }"
    EOF
  ]
}

data "kubectl_filename_list" "kube_state_metrics" {
  pattern = "${data.external.kube_state_metrics.result.manifests_dir}/examples/standard/*.yaml"
}

resource "kubernetes_manifest" "kube_state_metrics" {
  for_each = {
    for manifest in [
      for _, manifest_yaml_string in [
        for file_path in data.kubectl_filename_list.kube_state_metrics.matches : file(file_path) if !strcontains(file_path, "kustomization")
      ] : yamldecode(manifest_yaml_string)
      ] : join("|", compact([
        manifest.apiVersion,
        manifest.kind,
        lookup(lookup(manifest, "metadata", {}), "namespace", ""),
        lookup(lookup(manifest, "metadata", {}), "name", ""),
    ])) => manifest
  }
  manifest = each.value
}

data "http" "alert_rules" {
  url = "https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/${var.kube_prometheus_version}/manifests/kubernetesControlPlane-prometheusRule.yaml"
}

resource "kubernetes_manifest" "alert_rules" {
  for_each = {
    for manifest in [
      for _, manifest_yaml_string in [data.http.alert_rules.response_body] : yamldecode(manifest_yaml_string)
      ] : join("|", compact([
        manifest.apiVersion,
        manifest.kind,
        lookup(lookup(manifest, "metadata", {}), "namespace", ""),
        lookup(lookup(manifest, "metadata", {}), "name", ""),
    ])) => manifest
  }
  manifest = merge(
    each.value,
    {
      metadata = merge(
        each.value.metadata,
        {
          labels = merge(
            each.value.metadata.labels,
          )
          namespace = kubernetes_namespace.monitoring.metadata[0].name
        },
      )
      spec = merge(
        each.value.spec,
        {
          groups : [
            for group in each.value.spec.groups : merge(
              group,
              {
                rules : [
                  for rule in group.rules : rule if
                  !contains(keys(rule), "alert") || !contains(var.kube_prometheus_alerts_to_disable, lookup(rule, "alert", 0))
                ]
              }
            )
          ]
        },
      )
    },
  )
}

resource "kubernetes_manifest" "prometheus" {
  depends_on = [
    kubernetes_cluster_role_binding.prometheus,
    kubernetes_cluster_role.prometheus,
  ]
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "Prometheus"
    metadata = {
      name      = "prometheus"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      alerting = {
        alertmanagers = [
          {
            name      = "${kubernetes_manifest.alertmanager.manifest.metadata.name}-operated"
            namespace = kubernetes_manifest.alertmanager.manifest.metadata.namespace
            port      = "web"
          },
        ]
      }
      replicas = var.prometheus_replicas
      ruleNamespaceSelector = {
        matchLabels = {
          "kubernetes.io/metadata.name" = [for _, rule in kubernetes_manifest.alert_rules : rule][0].manifest.metadata.namespace
        }
      }
      ruleSelector = {
        matchLabels = [for _, rule in kubernetes_manifest.alert_rules : rule][0].manifest.metadata.labels
      }
      serviceAccountName = kubernetes_service_account.prometheus.metadata[0].name
      serviceMonitorNamespaceSelector = {
        matchLabels = {}
      }
      serviceMonitorSelector = {
        matchLabels = {}
      }
    }
  }
}

# For some reason, the service named "kubernetes" in namespace "default" fronts the API Server pod in the "kube-system" namespace.
data "kubernetes_service" "kubernetes" {
  metadata {
    name      = "kubernetes"
    namespace = "default"
  }
}

resource "kubernetes_manifest" "api_server_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "apiserver"
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      jobLabel = "component"
      namespaceSelector = {
        matchNames = [
          data.kubernetes_service.kubernetes.metadata[0].namespace
        ]
      }
      endpoints = [
        {
          authorization = {
            credentials = {
              key  = "token"
              name = kubernetes_secret.prometheus_service_account_token.metadata[0].name
            }
          }
          port   = "https"
          scheme = "https"
          tlsConfig = {
            ca = {
              secret = {
                key  = "ca.crt"
                name = kubernetes_secret.prometheus_service_account_token.metadata[0].name
              }
            }
          }
        },
      ]
      selector = {
        matchLabels = {
          component = "apiserver"
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_prometheus_egress_to_kubernetes_service" {
  metadata {
    name      = "allow-prometheus-egress-to-kubernetes-service"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    egress {
      to {
        dynamic "ip_block" {
          for_each = data.kubernetes_service.kubernetes.spec[0].cluster_ips
          iterator = cluster_ip
          content {
            cidr = "${cluster_ip.value}/32"
          }
        }
      }
      ports {
        port     = 6443
        protocol = "TCP"
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = kubernetes_manifest.prometheus.manifest.metadata.name
      }
    }
    policy_types = [
      "Egress",
    ]
  }
}
