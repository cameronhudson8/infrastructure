resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace_name
  }
}

locals {
  alertmanager_global_config_name = "global"
  alertmanager_config_name        = "main"
}

// Lima doesn't create a kube-controller-manager service. I haven't figured out why.
resource "kubernetes_service" "kube_controller_manager" {
  metadata {
    labels = {
      "app.kubernetes.io/name" = "kube-controller-manager"
    }
    name      = "kube-controller-manager"
    namespace = "kube-system"
  }
  spec {
    port {
      name = "https-metrics"
      port = 10257
    }
    selector = {
      component = "kube-controller-manager"
    }
  }
}

// Lima doesn't create a kube-scheduler service. I haven't figured out why.
resource "kubernetes_service" "kube_scheduler" {
  metadata {
    labels = {
      "app.kubernetes.io/name" = "kube-scheduler"
    }
    name      = "kube-scheduler"
    namespace = "kube-system"
  }
  spec {
    port {
      name = "https-metrics"
      port = 10259
    }
    selector = {
      component = "kube-scheduler"
    }
  }
}

data "external" "kube_prometheus_prepare_manifests" {
  program = [
    "/usr/bin/env",
    "bash",
    "-eu",
    "-o",
    "pipefail",
    "-c",
    # This script is based on the kube-prometheus installation docs.
    # https://github.com/prometheus-operator/kube-prometheus/blob/main/docs/customizing.md
    <<-EOF
      REPO='github.com/prometheus-operator/kube-prometheus'
      SUBDIR='jsonnet/kube-prometheus'
      MANIFESTS_PATH="${path.module}/kube-prometheus/manifests"
      MANIFESTS_SETUP_PATH="${path.module}/kube-prometheus/manifests/setup"

      mkdir -p "${path.module}/kube-prometheus"
      pushd "${path.module}/kube-prometheus" >/dev/null
      # Create the initial/empty `jsonnetfile.json'.
      if ! [ -f jsonnetfile.json ]; then
        jb init
      fi
      installed_version=$(
        jq -r \
          "
            .dependencies[] \
            | select(.source.git.remote == \"https://$${REPO}.git\" and .source.git.subdir == \"$${SUBDIR}\")
            | .version
          " \
          ./jsonnetfile.json
      )
      if [ "$${installed_version}" != '${var.kube_prometheus_version}' ]; then
        # Install the kube-prometheus dependency.
        # Creates `vendor/` and `jsonnetfile.lock.json`, and fills in `jsonnetfile.json`.
        jb -q install "$${REPO}/$${SUBDIR}@${var.kube_prometheus_version}"
      fi

      kube_prometheus_config_path="$(mktemp)"
      cat <<CONFIG >"$${kube_prometheus_config_path}"
      local kp =
        (import 'kube-prometheus/main.libsonnet')
        // Uncomment the following imports to enable its patches
        // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
        // (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
        // (import 'kube-prometheus/addons/node-ports.libsonnet') +
        // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
        // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
        // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
        // (import 'kube-prometheus/addons/pyrra.libsonnet') +
        {
          alertmanager+: {
            alertmanager+: {
              spec+: {
                // Send alerts through all routes and through all inhibition rules,
                // regardless of the namespace from which the alert originated.
                alertmanagerConfigMatcherStrategy+: {
                  type: 'None',
                },
                alertmanagerConfigNamespaceSelector+: {
                  // Look for AlertmanagerConfigs in all namespaces.
                  matchExpressions+: [
                    {
                      key: 'kubernetes.io/metadata.name',
                      operator: 'Exists',
                    },
                  ],
                },
                alertmanagerConfigSelector+: {
                  matchLabels+: {
                    name: '${local.alertmanager_config_name}',
                  },
                },
                alertmanagerConfiguration+: {
                  global+: {
                    httpConfig+: {
                      followRedirects: true,
                    },
                    resolveTimeout: '5m',
                    smtp+: {
                      hello: 'localhost',
                      requireTLS: true,
                    },
                  },
                  name: '${local.alertmanager_global_config_name}',
                  templates+: [],
                },
                // The Prometheus Operator will merge this into the list of containers based on the container name.
                containers+: [
                  {
                    name: 'config-reloader',
                    resources+: {
                      limits+: {
                        // VPA upperBound recommendation
                        cpu: '41m',
                      },
                      requests+: {
                        // VPA target recommendation
                        cpu: '12m',
                      },
                    },
                  },
                ],
                replicas: 1,
              },
            },
          },
          blackboxExporter+: {
            deployment+: {
              spec+: {
                template+: {
                  spec+: {
                    containers: [
                      (
                        if container.name == 'blackbox-exporter'
                        then container + {
                          resources+: {
                            limits+: {
                              // VPA upperBound recommendation
                              cpu: '160m',
                            },
                            requests+: {
                              // VPA target recommendation
                              cpu: '11m',
                            },
                          },
                        }
                        else container
                      ) for container in super.containers
                    ],
                  },
                },
              },
            },
          },
          prometheus+: {
            prometheus+: {
              spec+: {
                // The Prometheus Operator will merge this into the list of containers based on the container name.
                containers+: [
                  {
                    name: 'config-reloader',
                    resources+: {
                      limits+: {
                        // VPA upperBound recommendation
                        cpu: '41m',
                      },
                      requests+: {
                        // VPA target recommendation
                        cpu: '12m',
                      },
                    },
                  },
                ],
                remoteWrite+: [
                  {
                    name: 'mimir',
                    url: 'http://mimir-nginx:80/api/v1/push',
                  },
                ],
                replicas: 1,
                // This is needed to make the VPA happy.
                shards: 1,
              },
            },
          },
          values+:: {
            blackboxExporter+: {
              kubeRbacProxy+: {
                resources+: {
                  limits+: {
                    // VPA upperBound recommendation
                    cpu: '167m',
                  },
                  requests+: {
                    // VPA target recommendation
                    cpu: '11m',
                  },
                },
              },
            },
            common+: {
              // Use var.namespace_name here, so that manifest preparation can proceed
              // before the namespace has been created.
              namespace: '${var.namespace_name}',
            },
            kubeStateMetrics+: {
              kubeRbacProxyMain+: {
                resources+: {
                  limits+: {
                    cpu: '160m',
                  },
                  requests+: {
                    cpu: '11m',
                  },
                },
              },
              kubeRbacProxySelf+: {
                resources+: {
                  limits+: {
                    cpu: '167m',
                  },
                  requests+: {
                    cpu: '11m',
                  },
                },
              },
            },
            nodeExporter+: {
              kubeRbacProxy+: {
                resources+: {
                  limits+: {
                    cpu: '144m',
                  },
                  requests+: {
                    cpu: '12m',
                  },
                },
              },
            },
            prometheusOperator+: {
              kubeRbacProxy+: {
                resources+: {
                  limits+: {
                    cpu: '172m',
                  },
                  requests+: {
                    cpu: '12m',
                  },
                },
              },
            },
          },
        };

      // { 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
      {
        ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
        for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
      } +
      // { 'setup/pyrra-slo-CustomResourceDefinition': kp.pyrra.crd } +
      // serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
      { 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
      { 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
      { 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
      { ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
      { ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
      // { ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
      // { ['pyrra-' + name]: kp.pyrra[name] for name in std.objectFields(kp.pyrra) if name != 'crd' } +
      { ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
      { ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
      { ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
      { ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
      { ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
      CONFIG

      manifests_checksum=$(cat "$${kube_prometheus_config_path}" $(find -E "$${MANIFESTS_PATH}" -regex '.*\.ya?ml') | md5 -q)
      manifests_setup_checksum=$(cat "$${kube_prometheus_config_path}" $(find -E "$${MANIFESTS_SETUP_PATH}" -regex '.*\.ya?ml') | md5 -q)

      curl 'https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/${var.kube_prometheus_version}/build.sh' \
          --fail-with-body \
          -LsS \
          | sh -s "$${kube_prometheus_config_path}"
      output=$(
        cat <<JSON
          {
              "manifests_checksum": "$${manifests_checksum}",
              "manifests_path": "$${MANIFESTS_PATH}",
              "manifests_setup_checksum": "$${manifests_setup_checksum}",
              "manifests_setup_path": "$${MANIFESTS_SETUP_PATH}"
          }
      JSON
      )
      jq -cM '.' <<<"$${output}"
    EOF
  ]
}

resource "kubernetes_secret" "email_sender_creds" {
  metadata {
    name      = "monitoring-email-sender-creds"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    password = var.email_sender_password
    username = var.email_sender_email_address
  }
}


resource "kubernetes_manifest" "alertmanager_config_global" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      labels = {
        name = local.alertmanager_global_config_name
      }
      name      = local.alertmanager_global_config_name
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      receivers = [
        {
          name = "null"
        },
      ]
      route = {
        receiver = "null"
      }
    }
  }
}

resource "kubernetes_manifest" "alertmanager_config" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      labels = {
        name = local.alertmanager_config_name
      }
      name      = local.alertmanager_config_name
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    spec = {
      inhibitRules = [
        {
          equal = [
            "alertname",
            "namespace",
          ]
          sourceMatchers = [
            "severity=\"critical\"",
          ]
          targetMatchers = [
            "severity=~\"warning|info\"",
          ]
        },
        {
          equal = [
            "alertname",
            "namespace",
          ]
          sourceMatchers = [
            "severity=\"warning\"",
          ]
          targetMatchers = [
            "severity=\"info\"",
          ]
        },
        {
          equal = [
            "namespace",
          ]
          sourceMatchers = [
            "alertname=\"InfoInhibitor\"",
          ]
          targetMatchers = [
            "severity=\"info\"",
          ]
        },
      ]
      receivers = [
        {
          name = "null"
        },
        {
          emailConfigs = [
            {
              authPassword = {
                name = kubernetes_secret.email_sender_creds.metadata[0].name
                key  = "password"
              }
              authUsername = var.email_sender_email_address
              headers = [
                {
                  key   = "subject"
                  value = "Prometheus Alert"
                }
              ]
              from         = var.email_sender_email_address
              sendResolved = true
              smarthost    = var.email_sender_transport
              to           = var.email_recipient_email_address
            }
          ]
          name = "email"
        }
      ]
      route = {
        groupBy = [
          "namespace",
        ]
        groupInterval  = "5m"
        groupWait      = "30s"
        receiver       = "null"
        repeatInterval = "12h"
        routes = [
          {
            continue = false
            matchers = [
              {
                matchType = "="
                name      = "alertname"
                value     = "Watchdog"
              }
            ]
            receiver = "null"
          },
          {
            continue = false
            matchers = [
              {
                matchType = "="
                name      = "alertname"
                value     = "InfoInhibitor"
              }
            ]
            receiver = "null"
          },
          {
            groupBy = [
              "job",
            ]
            receiver = "email"
          }
        ]
      }
    }
  }
}

resource "kubernetes_manifest" "kube_prometheus_setup" {
  depends_on = [
    kubernetes_manifest.alertmanager_config,
  ]
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_setup_path, path.module, "./")}/*") :
        yamldecode(file("${path.module}/${file_path}"))
      ] :
      _manifest if !contains(["CustomResourceDefinition", "Namespace"], _manifest.kind)
    ] :
    join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      try("namespace=${manifest.metadata.namespace}", ""),
      try("name=${manifest.metadata.name}", ""),
    ]))
    => manifest
  }
  manifest = each.value
}

resource "kubernetes_manifest" "kube_prometheus" {
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup,
  ]
  for_each = {
    for manifest in flatten([
      # Some of the files contain "List" aggregate resources that do not exist in the Kubernetes API. Split them.
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_path, path.module, "./")}/*") :
        yamldecode(file("${path.module}/${file_path}"))
      ] :
      # This is the most sensible way, but Terraform throws "Inconsistent conditional result types".
      # (
      #   endswith(_manifest.kind, "List")
      #   ? _manifest.items
      #   : [_manifest]
      # )
      lookup(_manifest, "items", [_manifest])
    ]) :
    join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      try("namespace=${manifest.metadata.namespace}", ""),
      try("name=${manifest.metadata.name}", ""),
    ]))
    => manifest
  }
  manifest = each.value
  # Workarounds for bugs in provider
  computed_fields = concat(
    compact([
      "metadata.annotations",
      "metadata.labels",
      can(each.value.metadata.annotations["deprecated.daemonset.template.generation"]) ? "metadata.annotations[\"deprecated.daemonset.template.generation\"]" : "",
      can(each.value.spec.template.spec.containers[0].env) ? "spec.template.spec.containers[0].env" : "",
      can(each.value.stringData) ? "stringData" : "",
    ]),
    [
      for v in range(0, length(try(each.value.spec.template.spec.containers[0].volumeMounts, [])), 1) :
      "spec.template.spec.containers[0].volumeMounts[${v}].readOnly"
    ],
  )
}

resource "helm_release" "loki" {
  chart      = "loki-distributed"
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  values = [
    yamlencode({
      loki = {
        structuredConfig = {
          limits_config = {
            volume_enabled = true
          }
        }
      }
    })
  ]
  version = var.loki_distributed_helm_chart_version
}

resource "helm_release" "tempo" {
  chart      = "tempo-distributed"
  name       = "tempo"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  values = [
    yamlencode({
      ingester = merge(
        var.tempo_ingester_replicas == null ? {} : { replicas = var.tempo_ingester_replicas },
      )
    })
  ]
  version = var.tempo_distributed_helm_chart_version
}

# Get the default Helm chart values, so we can create persistent volumes of
# appropriate sizes.
data "http" "mimir_distributed_helm_chart_default_values" {
  url = "https://raw.githubusercontent.com/grafana/mimir/refs/tags/mimir-distributed-${var.mimir_distributed_helm_chart_version}/operations/helm/charts/mimir-distributed/values.yaml"
}

locals {
  mimir_distributed_helm_chart_default_values = yamldecode(data.http.mimir_distributed_helm_chart_default_values.response_body)
  mimir = {
    ingester_zone_aware_replication_enabled = (
      var.mimir_zone_aware_replication != null
      ? var.mimir_zone_aware_replication
      : local.mimir_distributed_helm_chart_default_values.ingester.zoneAwareReplication.enabled
    )
    store_gateway_zone_aware_replication_enabled = (
      var.mimir_zone_aware_replication != null
      ? var.mimir_zone_aware_replication
      : local.mimir_distributed_helm_chart_default_values.store_gateway.zoneAwareReplication.enabled
    )
  }
  mimir_volumes = concat(
    [
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.minio.persistence.size
        host_path        = "/mnt/mimir-minio"
        pv_name          = "mimir-minio"
        pvc_name         = "mimir-minio"
      },
    ],
    [
      for replica in range(local.mimir_distributed_helm_chart_default_values.alertmanager.replicas) :
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.alertmanager.persistentVolume.size
        host_path        = "/mnt/storage-mimir-alertmanager-${replica}"
        pv_name          = "storage-mimir-alertmanager-${replica}"
        pvc_name         = "storage-mimir-alertmanager-${replica}"
      }
    ],
    [
      for replica in range(local.mimir_distributed_helm_chart_default_values.compactor.replicas) :
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.compactor.persistentVolume.size
        host_path        = "/mnt/storage-mimir-compactor-${replica}"
        pv_name          = "storage-mimir-compactor-${replica}"
        pvc_name         = "storage-mimir-compactor-${replica}"
      }
    ],
    local.mimir.ingester_zone_aware_replication_enabled
    ? flatten([
      for zone in local.mimir_distributed_helm_chart_default_values.ingester.zoneAwareReplication.zones :
      [
        for replica in range(ceil(var.mimir_ingester_replicas != null ? var.mimir_ingester_replicas : local.mimir_distributed_helm_chart_default_values.ingester.replicas) / 3) :
        {
          default_capacity = local.mimir_distributed_helm_chart_default_values.ingester.persistentVolume.size
          host_path        = "/mnt/storage-mimir-ingester-${zone.name}-${replica}"
          pv_name          = "storage-mimir-ingester-${zone.name}-${replica}"
          pvc_name         = "storage-mimir-ingester-${zone.name}-${replica}"
        }
      ]
    ])
    : [
      for replica in range(var.mimir_ingester_replicas != null ? var.mimir_ingester_replicas : local.mimir_distributed_helm_chart_default_values.ingester.replicas) :
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.ingester.persistentVolume.size
        host_path        = "/mnt/storage-mimir-ingester-${replica}"
        pv_name          = "storage-mimir-ingester-${replica}"
        pvc_name         = "storage-mimir-ingester-${replica}"
      }
    ],
    local.mimir.store_gateway_zone_aware_replication_enabled
    ? [
      for zone in local.mimir_distributed_helm_chart_default_values.store_gateway.zoneAwareReplication.zones :
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.store_gateway.persistentVolume.size
        host_path        = "/mnt/storage-mimir-store-gateway-${zone.name}-0"
        pv_name          = "storage-mimir-store-gateway-${zone.name}-0"
        pvc_name         = "storage-mimir-store-gateway-${zone.name}-0"
      }
    ]
    : [
      {
        default_capacity = local.mimir_distributed_helm_chart_default_values.store_gateway.persistentVolume.size
        host_path        = "/mnt/storage-mimir-store-gateway-0"
        pv_name          = "storage-mimir-store-gateway-0"
        pvc_name         = "storage-mimir-store-gateway-0"
      },
    ],
  )
}

resource "terraform_data" "host_paths" {
  for_each = {
    for volume in local.mimir_volumes : volume.pvc_name => volume
  }
  input = {
    host_path = each.value.host_path
    vm_name   = var.vm_name
  }
  provisioner "local-exec" {
    command = "limactl shell ${self.input.vm_name} sudo mkdir -p ${self.input.host_path}"
    when    = create
  }
  provisioner "local-exec" {
    command = "limactl shell ${self.input.vm_name} sudo rm -rf ${self.input.host_path}"
    when    = destroy
  }
}

resource "kubernetes_persistent_volume" "mimir_volumes" {
  for_each = {
    for volume in local.mimir_volumes : volume.pvc_name => volume
  }
  metadata {
    name = each.value.pv_name
  }
  spec {
    access_modes = [
      "ReadWriteOnce",
    ]
    capacity = {
      storage = each.value.default_capacity
    }
    claim_ref {
      name      = each.value.pvc_name
      namespace = kubernetes_namespace.monitoring.metadata[0].name
    }
    node_affinity {
      required {
        node_selector_term {
          # Match any node
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "Exists"
          }
        }
      }
    }
    persistent_volume_source {
      local {
        path = each.value.host_path
      }
    }
    storage_class_name = var.storage_class_name
  }
}

resource "helm_release" "mimir" {
  depends_on = [
    terraform_data.host_paths,
  ]
  chart      = "mimir-distributed"
  name       = "mimir"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  values = [
    yamlencode({
      minio = {
        persistence = {
          size = local.mimir_distributed_helm_chart_default_values.minio.persistence.size
        }
      }
      alertmanager = {
        persistentVolume = {
          size = local.mimir_distributed_helm_chart_default_values.alertmanager.persistentVolume.size
        }
      }
      compactor = {
        persistentVolume = {
          size = local.mimir_distributed_helm_chart_default_values.compactor.persistentVolume.size
        }
      }
      ingester = merge(
        {
          persistentVolume = {
            size = local.mimir_distributed_helm_chart_default_values.ingester.persistentVolume.size
          }
          zoneAwareReplication = merge(
            var.mimir_zone_aware_replication == null ? {} : { enabled = var.mimir_zone_aware_replication },
          )
        },
        var.mimir_ingester_replicas == null ? {} : { replicas = var.mimir_ingester_replicas },
      )
      querier = merge(
        var.mimir_querier_replicas == null ? {} : { replicas = var.mimir_querier_replicas },
      )
      query_scheduler = merge(
        var.mimir_query_scheduler_replicas == null ? {} : { replicas = var.mimir_query_scheduler_replicas }
      )
      store_gateway = {
        persistentVolume = {
          size = local.mimir_distributed_helm_chart_default_values.store_gateway.persistentVolume.size
        }
        zoneAwareReplication = merge(
          var.mimir_zone_aware_replication == null ? {} : { enabled = var.mimir_zone_aware_replication },
        )
      }
    })
  ]
  version = var.mimir_distributed_helm_chart_version
}

locals {
  grafana_dashboard_filenames = fileset("${path.module}/grafana-dashboards", "*.json")
}

resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    namespace = var.namespace_name
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
  chart      = "grafana"
  name       = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
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
        (local.dashboard_provider_name) = "grafana-dashboards"
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
    })
  ]
  version = var.grafana_helm_chart_version
}

# Create a VPA (with mode: "Off") for each workload.

# This list was generated manually with the command below.
# TODO: Automate this somehow. Maybe the dependencies have a feature that deploys VPAs.
#     kubectl get pod \
#         --context local \
#         --namespace monitoring \
#         --output yaml \
#     | yq \
#         --exit-status \
#         --output-format json \
#         '
#             .
#             | .items
#             | map(.metadata.ownerReferences[0])
#             | map({ "apiVersion": .apiVersion, "kind": .kind, "name": .name })
#             | map(
#                 .
#                 | with(
#                     select(.kind == "ReplicaSet");
#                     .
#                     | .kind = "Deployment"
#                     | .name = (.name | sub("-\\w+$"; ""))
#                 )
#                 | with(
#                     select(.name == "alertmanager-main");
#                     .
#                     | .apiVersion = "monitoring.coreos.com/v1"
#                     | .kind = "Alertmanager"
#                     | .name = "main"
#                 )
#                 | with(
#                     select(.name == "prometheus-k8s");
#                     .
#                     | .apiVersion = "monitoring.coreos.com/v1"
#                     | .kind = "Prometheus"
#                     | .name = "k8s"
#                 )
#             )
#             | unique_by(.)
#             | sort_by(.apiVersion, .kind, .name)
#          ' \
#     | sed -E 's/"(.+)":/\1 =/g'
locals {
  vpa_configs = concat(
    [
      {
        apiVersion = "apps/v1",
        kind       = "DaemonSet",
        name       = "node-exporter"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "blackbox-exporter"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "grafana"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "kube-state-metrics"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "loki-loki-distributed-distributor"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "loki-loki-distributed-gateway"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "loki-loki-distributed-query-frontend"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-distributor"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-minio"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-nginx"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-overrides-exporter"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-querier"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-query-frontend"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-query-scheduler"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-rollout-operator"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "mimir-ruler"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "prometheus-adapter"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "prometheus-operator"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "tempo-compactor"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "tempo-distributor"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "tempo-querier"
      },
      {
        apiVersion = "apps/v1",
        kind       = "Deployment",
        name       = "tempo-query-frontend"
      },
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "loki-loki-distributed-ingester"
      },
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "loki-loki-distributed-querier"
      },
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-alertmanager"
      },
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-compactor"
      },
    ],
    (var.mimir_zone_aware_replication == null || var.mimir_zone_aware_replication == true)
    ? [
      for zone in ["a", "b", "c"] :
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-ingester-zone-${zone}"
      }
    ]
    : [
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-ingester"
      },
    ],
    (var.mimir_zone_aware_replication == null || var.mimir_zone_aware_replication == true)
    ? [
      for zone in ["a", "b", "c"] :
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-store-gateway-zone-${zone}"
      }
    ]
    : [
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "mimir-store-gateway"
      },
    ],
    [
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "tempo-ingester"
      },
      {
        apiVersion = "apps/v1",
        kind       = "StatefulSet",
        name       = "tempo-memcached"
      },
      {
        apiVersion = "batch/v1",
        kind       = "Job",
        name       = "mimir-make-minio-buckets-5.3.0"
      },
      {
        apiVersion = "monitoring.coreos.com/v1",
        kind       = "Alertmanager",
        name       = "main"
      },
      {
        apiVersion = "monitoring.coreos.com/v1",
        kind       = "Prometheus",
        name       = "k8s"
      }
    ]
  )
}

resource "kubernetes_manifest" "vpas" {
  for_each = {
    for vpa_config in local.vpa_configs :
    join(",", [
      "apiVersion=${vpa_config.apiVersion}",
      "kind=${vpa_config.kind}",
      "namespace=${kubernetes_namespace.monitoring.metadata[0].name}",
      "name=${vpa_config.name}",
    ]) => vpa_config
  }
  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      namespace = kubernetes_namespace.monitoring.metadata[0].name
      name      = "${lower(each.value.kind)}-${each.value.name}"
    }
    spec = {
      targetRef = {
        apiVersion = each.value.apiVersion
        kind       = each.value.kind
        name       = each.value.name
      }
      updatePolicy = {
        updateMode = "Off"
      }
    }
  }
}
