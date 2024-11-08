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

      { 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
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
      { ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
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
      jq -cM '.' <<JSON
          {
              "manifests_checksum": "$${manifests_checksum}",
              "manifests_path": "$${MANIFESTS_PATH}",
              "manifests_setup_checksum": "$${manifests_setup_checksum}",
              "manifests_setup_path": "$${MANIFESTS_SETUP_PATH}"
          }
      JSON
    EOF
  ]
}

resource "kubernetes_manifest" "kube_prometheus_setup_namespaces" {
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_setup_path, path.module, "./")}/*")
        : yamldecode(file("${path.module}/${file_path}"))
      ]
      : _manifest if contains(["Namespace"], _manifest.kind)
    ]
    : join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      try("namespace=${manifest.metadata.namespace}", ""),
      try("name=${manifest.metadata.name}", ""),
    ]))
    => manifest
  }
  manifest = each.value
}

resource "kubernetes_secret" "email_sender_creds" {
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup_namespaces,
  ]
  metadata {
    name      = "monitoring-email-sender-creds"
    namespace = var.namespace_name
  }
  data = {
    password = var.email_sender_auth_password
    username = var.email_sender_auth_username
  }
}


resource "kubernetes_manifest" "alertmanager_config_global" {
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup_namespaces,
  ]
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      labels = {
        name = local.alertmanager_global_config_name
      }
      name      = local.alertmanager_global_config_name
      namespace = var.namespace_name
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
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup_namespaces,
  ]
  manifest = {
    apiVersion = "monitoring.coreos.com/v1alpha1"
    kind       = "AlertmanagerConfig"
    metadata = {
      labels = {
        name = local.alertmanager_config_name
      }
      name      = local.alertmanager_config_name
      namespace = var.namespace_name
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
              authUsername = var.email_sender_auth_username
              headers = [
                {
                  key   = "subject"
                  value = "Prometheus Alert"
                }
              ]
              from         = var.email_sender.address
              sendResolved = true
              smarthost    = var.email_sender.transport
              to           = var.email_recipient_address
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

resource "kubernetes_manifest" "kube_prometheus_setup_remaining" {
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup_namespaces,
    kubernetes_manifest.alertmanager_config,
  ]
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_setup_path, path.module, "./")}/*")
        : yamldecode(file("${path.module}/${file_path}"))
      ]
      : _manifest if !contains(["CustomResourceDefinition", "Namespace"], _manifest.kind)
    ]
    : join(",", compact([
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
    kubernetes_manifest.kube_prometheus_setup_namespaces,
    kubernetes_manifest.kube_prometheus_setup_remaining,
  ]
  for_each = {
    for manifest in flatten([
      # Some of the files contain "List" aggregate resources that do not exist in the Kubernetes API. Split them.
      for _manifest in [
        for file_path in fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_path, path.module, "./")}/*")
        : yamldecode(file("${path.module}/${file_path}"))
      ]
      # This is the most sensible way, but Terraform throws "Inconsistent conditional result types".
      # : (
      #   endswith(_manifest.kind, "List")
      #   ? _manifest.items
      #   : [_manifest]
      # )
      : lookup(_manifest, "items", [_manifest])
    ])
    : join(",", compact([
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
      for v in range(0, length(try(each.value.spec.template.spec.containers[0].volumeMounts, [])), 1)
      : "spec.template.spec.containers[0].volumeMounts[${v}].readOnly"
    ],
  )
}

# Create a VPA (with mode: "Off") for workload.
resource "kubernetes_manifest" "vpas" {
  depends_on = [
    kubernetes_manifest.kube_prometheus_setup_namespaces,
    kubernetes_manifest.kube_prometheus_setup_remaining,
  ]
  for_each = {
    for manifest in [
      for _manifest in [
        for file_path in flatten([
          fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_path, path.module, "./")}/*"),
          fileset(path.module, "${replace(data.external.kube_prometheus_prepare_manifests.result.manifests_setup_path, path.module, "./")}/*"),
        ])
        : yamldecode(file("${path.module}/${file_path}"))
      ]
      : _manifest if(
        _manifest.apiVersion == "apps/v1" && _manifest.kind == "Deployment"
        || _manifest.apiVersion == "apps/v1" && _manifest.kind == "DaemonSet"
        || _manifest.apiVersion == "monitoring.coreos.com/v1" && _manifest.kind == "Alertmanager"
        || _manifest.apiVersion == "monitoring.coreos.com/v1" && _manifest.kind == "Prometheus"
      )
    ]
    : join(",", compact([
      "apiVersion=${manifest.apiVersion}",
      "kind=${manifest.kind}",
      try("namespace=${manifest.metadata.namespace}", ""),
      try("name=${manifest.metadata.name}", ""),
    ]))
    => manifest
  }
  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      namespace = each.value.metadata.namespace
      name      = "${lower(each.value.kind)}-${each.value.metadata.name}"
    }
    spec = {
      targetRef = {
        apiVersion = each.value.apiVersion
        kind       = each.value.kind
        name       = each.value.metadata.name
      }
      updatePolicy = {
        updateMode = "Off"
      }
    }
  }
}
