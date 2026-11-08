# Unnamespaced resources (including CRDs)

data "helm_template" "kube_prometheus_stack" {
  chart        = "kube-prometheus-stack"
  kube_version = var.kubernetes_version
  name         = "kube-prometheus-stack"
  repository   = "oci://ghcr.io/prometheus-community/charts"
  version      = var.kube_prometheus_version
}

resource "kubernetes_manifest" "kube_prometheus_crds" {
  for_each = {
    for crd in [
      for crd_yaml in data.helm_template.kube_prometheus_stack.crds : yamldecode(crd_yaml)
      ] : join(",", compact([
        "apiVersion=${crd.apiVersion}",
        "kind=${crd.kind}",
        try("namespace=${crd.metadata.namespace}", ""),
        try("name=${crd.metadata.name}", ""),
    ]))
    => crd
  }
  manifest = each.value
}

# Namespaced resources

resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

resource "kubernetes_secret_v1" "email_sender_creds" {
  metadata {
    name      = "observability-email-sender-creds"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  data = {
    password = var.email_sender_password
    username = var.email_sender_email_address
  }
}

locals {
  control_plane_cidrs = flatten([
    for subset in data.kubernetes_endpoints_v1.kubernetes.subset :
    [for address in subset.address : "${address.ip}/${length(regexall(":", address.ip)) > 0 ? 128 : 32}"]
  ])
}

resource "kubernetes_network_policy_v1" "allow_kube_state_metrics_egress_to_control_plane" {
  metadata {
    name      = "allow-kube-state-metrics-egress-to-control-plane"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      to {
        dynamic "ip_block" {
          for_each = local.control_plane_cidrs
          content {
            cidr = ip_block.value
          }
        }
      }
    }
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "metrics"
        "app.kubernetes.io/instance"  = "kube-prometheus-stack"
      }
    }
    policy_types = ["Egress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_kube_prometheus_egress_to_control_plane" {
  metadata {
    name      = "allow-kube-prometheus-egress-to-control-plane"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }
  spec {
    egress {
      ports {
        port     = 443
        protocol = "TCP"
      }
      to {
        dynamic "ip_block" {
          for_each = local.control_plane_cidrs
          content {
            cidr = ip_block.value
          }
        }
      }
    }
    pod_selector {
      match_expressions {
        key      = "app"
        operator = "In"
        values = [
          "kube-prometheus-stack-admission-create",
          "kube-prometheus-stack-admission-patch",
          "kube-prometheus-stack-operator",
        ]
      }
    }
    policy_types = ["Egress"]
  }
}

resource "helm_release" "kube_prometheus_stack" {
  atomic     = true
  chart      = "kube-prometheus-stack"
  depends_on = [kubernetes_network_policy_v1.allow_kube_prometheus_egress_to_control_plane]
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "oci://ghcr.io/prometheus-community/charts"
  skip_crds  = true
  values = [
    yamlencode({
      alertmanager = {
        alertmanagerSpec = {
          secrets = [kubernetes_secret_v1.email_sender_creds.metadata[0].name]
        }
        config = {
          global = {
            resolve_timeout = "5m"
          }
          inhibit_rules = [
            {
              equal = [
                "alertname",
                "namespace",
              ]
              source_matchers = ["severity = \"critical\""]
              target_matchers = ["severity =~ \"warning|info\""]
            },
            {
              equal = [
                "alertname",
                "namespace",
              ]
              source_matchers = ["severity = \"warning\""]
              target_matchers = ["severity = \"info\""]
            },
            {
              equal           = ["namespace"]
              source_matchers = ["alertname = \"InfoInhibitor\""]
              target_matchers = ["severity = \"info\""]
            },
          ]
          receivers = [
            { name = "null" },
            {
              email_configs = [{
                auth_password_file = "/etc/alertmanager/secrets/observability-email-sender-creds/password"
                auth_username      = var.email_sender_email_address
                from               = var.email_sender_email_address
                headers = [{
                  key   = "subject"
                  value = "Prometheus Alert"
                }]
                send_resolved = true
                smarthost     = var.email_sender_transport
                to            = var.email_recipient_email_address
              }]
              name = "email"
            },
          ]
          route = {
            group_by        = ["namespace"]
            group_interval  = "5m"
            group_wait      = "30s"
            receiver        = "null"
            repeat_interval = "12h"
            routes = [
              {
                matchers = ["alertname = \"Watchdog\""]
                receiver = "null"
              },
              {
                matchers = ["alertname = \"InfoInhibitor\""]
                receiver = "null"
              },
              {
                group_by = ["job"]
                receiver = "email"
              },
            ]
          }
          templates = ["/etc/alertmanager/config/*.tmpl"]
        }
      }
    })
  ]
  version = var.kube_prometheus_version
}

data "kubernetes_endpoints_v1" "kubernetes" {
  metadata {
    name      = "kubernetes"
    namespace = "default"
  }
}

# Loki

resource "helm_release" "loki" {
  atomic     = true
  chart      = "loki"
  name       = "loki"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://grafana-community.github.io/helm-charts"
  values = [
    yamlencode({
      deploymentMode = "Distributed"
      loki = {
        storage = {
          bucketNames = {
            admin  = "admin"
            chunks = "chunks"
            ruler  = "ruler"
          }
        }
      }
    })
  ]
  version = var.loki_helm_chart_version
}

# Tempo

resource "helm_release" "tempo_distributed" {
  atomic     = true
  chart      = "tempo-distributed"
  name       = "tempo-distributed"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://grafana-community.github.io/helm-charts"
  values = [
    yamlencode({
      global = {
        storageClass = "standard-rwo"
      }
    })
  ]
  version = var.tempo_distributed_helm_chart_version
}

# Mimir

module "mimir" {
  helm_chart_version = var.mimir_distributed_helm_chart_version
  namespace_name     = "observability"
  source             = "./mimir"
}

# Grafana

locals {
  grafana_dashboard_filenames = fileset("${path.module}/grafana-dashboards", "*.json")
}

resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    name      = "grafana-dashboards"
  }
  data = {
    for filename in local.grafana_dashboard_filenames :
    (filename) => file("${path.module}/grafana-dashboards/${filename}")
  }
}

locals {
  dashboard_provider_name = "kubernetes-config-maps"
}

resource "helm_release" "grafana" {
  atomic     = true
  chart      = "grafana"
  name       = "grafana"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://grafana-community.github.io/helm-charts"
  values = [
    yamlencode({
      dashboardProviders = {
        "dashboardproviders.yaml" = {
          apiVersion = 1
          providers = [
            {
              disableDeletion = true
              editable        = false
              folder          = ""
              name            = local.dashboard_provider_name
              options = {
                path = "/var/lib/grafana/dashboards/${local.dashboard_provider_name}"
              }
              type = "file"
            }
          ]
        }
      }
      dashboardsConfigMaps = {
        (local.dashboard_provider_name) = kubernetes_config_map_v1.grafana_dashboards.metadata[0].name
      }
      # Based on https://github.com/grafana/helm-charts/blob/main/charts/lgtm-distributed/values.yaml
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              editable  = false,
              isDefault = false
              name      = "Loki",
              type      = "loki",
              uid       = "loki"
              url       = "http://loki-loki-distributed-gateway:80"
            },
            {
              editable  = false,
              isDefault = true
              name      = "Mimir",
              type      = "prometheus",
              uid       = "mimir"
              url       = "http://mimir-nginx:80/prometheus"
            },
            {
              editable  = false,
              isDefault = false
              jsonData = {
                lokiSearch = {
                  datasourceUid = "loki"
                }
                tracesToLogsV2 = {
                  datasourceUid = "loki"
                }
                tracesToMetrics = {
                  datasourceUid = "mimir"
                }
                serviceMap = {
                  datasourceUid = "mimir"
                }
              }
              name = "Tempo",
              type = "tempo",
              uid  = "tempo"
              url  = "http://tempo-query-frontend:3100"
            },
          ]
        }
      }
      env = {
        TZ = "America/Los_Angeles"
      }
      persistence = {
        enabled          = true
        storageClassName = "standard-rwo"
      }
    })
  ]
  version = var.grafana_helm_chart_version
}


# Fluentd

module "fluentd" {
  env_name                   = var.env_name
  fluentd_version            = var.fluentd_version
  loki_distributor_name      = "loki-loki-distributed-distributor"
  loki_distributor_namespace = kubernetes_namespace_v1.observability.metadata[0].name
  loki_distributor_port      = 3100
  namespace_name             = "observability"
  source                     = "./fluentd"
}

# # Create a VPA (with mode: "Off") for each workload.

# # This list was generated manually with the command below.
# # TODO: Automate this somehow. Maybe the dependencies have a feature that deploys VPAs.
# #     kubectl get pod \
# #         --context local \
# #         --namespace observability \
# #         --output yaml \
# #     | yq \
# #         --exit-status \
# #         --output-format json \
# #         '
# #             .
# #             | .items
# #             | map(.metadata.ownerReferences[0])
# #             | map({ "apiVersion": .apiVersion, "kind": .kind, "name": .name })
# #             | map(
# #                 .
# #                 | with(
# #                     select(.kind == "ReplicaSet");
# #                     .
# #                     | .kind = "Deployment"
# #                     | .name = (.name | sub("-\\w+$"; ""))
# #                 )
# #                 | with(
# #                     select(.name == "alertmanager-main");
# #                     .
# #                     | .apiVersion = "monitoring.coreos.com/v1"
# #                     | .kind = "Alertmanager"
# #                     | .name = "main"
# #                 )
# #                 | with(
# #                     select(.name == "prometheus-k8s");
# #                     .
# #                     | .apiVersion = "monitoring.coreos.com/v1"
# #                     | .kind = "Prometheus"
# #                     | .name = "k8s"
# #                 )
# #             )
# #             | unique_by(.)
# #             | sort_by(.apiVersion, .kind, .name)
# #          ' \
# #     | sed -E 's/"(.+)":/\1 =/g'
# locals {
#   vpa_configs = concat(
#     [
#       {
#         apiVersion = "apps/v1"
#         kind       = "DaemonSet"
#         name       = "node-exporter"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "blackbox-exporter"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "grafana"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "kube-state-metrics"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "loki-loki-distributed-distributor"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "loki-loki-distributed-gateway"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "loki-loki-distributed-query-frontend"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-distributor"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-minio"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-nginx"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-overrides-exporter"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-querier"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-query-frontend"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-query-scheduler"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-rollout-operator"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "mimir-ruler"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "prometheus-adapter"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "prometheus-operator"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "tempo-compactor"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "tempo-distributor"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "tempo-querier"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "Deployment"
#         name       = "tempo-query-frontend"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "loki-loki-distributed-ingester"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "loki-loki-distributed-querier"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-alertmanager"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-compactor"
#       },
#     ],
#     (var.mimir_zone_aware_replication == null || var.mimir_zone_aware_replication == true)
#     ? [
#       for zone in ["a", "b", "c"] :
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-ingester-zone-${zone}"
#       }
#     ]
#     : [
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-ingester"
#       },
#     ],
#     (var.mimir_zone_aware_replication == null || var.mimir_zone_aware_replication == true)
#     ? [
#       for zone in ["a", "b", "c"] :
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-store-gateway-zone-${zone}"
#       }
#     ]
#     : [
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "mimir-store-gateway"
#       },
#     ],
#     [
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "tempo-ingester"
#       },
#       {
#         apiVersion = "apps/v1"
#         kind       = "StatefulSet"
#         name       = "tempo-memcached"
#       },
#       {
#         apiVersion = "batch/v1"
#         kind       = "Job"
#         name       = "mimir-make-minio-buckets-5.3.0"
#       },
#       {
#         apiVersion = "monitoring.coreos.com/v1"
#         kind       = "Alertmanager"
#         name       = "main"
#       },
#       {
#         apiVersion = "monitoring.coreos.com/v1"
#         kind       = "Prometheus"
#         name       = "k8s"
#       }
#     ]
#   )
# }

# resource "kubernetes_manifest" "vpas" {
#   for_each = {
#     for vpa_config in local.vpa_configs :
#     join(",", [
#       "apiVersion=${vpa_config.apiVersion}",
#       "kind=${vpa_config.kind}",
#       "namespace=${kubernetes_namespace_v1.observability.metadata[0].name}",
#       "name=${vpa_config.name}",
#     ]) => vpa_config
#   }
#   manifest = {
#     apiVersion = "autoscaling.k8s.io/v1"
#     kind       = "VerticalPodAutoscaler"
#     metadata = {
#       namespace = kubernetes_namespace_v1.observability.metadata[0].name
#       name      = "${lower(each.value.kind)}-${each.value.name}"
#     }
#     spec = {
#       targetRef = {
#         apiVersion = each.value.apiVersion
#         kind       = each.value.kind
#         name       = each.value.name
#       }
#       updatePolicy = {
#         updateMode = "Off"
#       }
#     }
#   }
# }
