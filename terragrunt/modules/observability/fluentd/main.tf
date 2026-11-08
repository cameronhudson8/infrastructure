# Inspired by https://medium.com/@Oskarr3/feeding-loki-with-fluentd-4e9647d23ab9
resource "kubernetes_config_map" "fluentd" {
  metadata {
    labels = {
      app     = "fluentd"
      version = "v${var.fluentd_version}"
    }
    name      = "fluentd"
    namespace = var.namespace_name
  }
  data = {
    "fluent.conf" = <<-EOF
      # Node logs
      <source>
        @type tail
        @id node_logs
        path /var/log/*.log
        pos_file /var/log/fluentd-node-logs.log.pos
        tag node.*
        # Example format
        #     2025-04-19T15:42:31.038315-07:00 lima-k8s kernel: kauditd_printk_skb: 42 callbacks suppressed
        <parse>
          @type regexp
          # Regex Breakdown:
          # ^                                                                # Anchor to start of line
          # (?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[-+]\d{2}:\d{2}) # Capture timestamp with nanoseconds and timezone
          # \s+                                                              # Match space(s)
          # (?<message>.*)                                                   # Capture the rest of the message greedily
          # $                                                                # Anchor to end of line
          expression /^(?<time>[^ ]+)\s+(?<message>.*)$/
          time_key time
          time_format %Y-%m-%dT%H:%M:%S.%N%:z
          keep_time_key true
          # Define data types for captured fields (optional but recommended)
          types message:string
        </parse>
      </source>
      <match node.**>
        @type loki
        <buffer>
          flush_interval 10s
          flush_at_shutdown true
        </buffer>
        extra_labels {"env":"${var.env_name}","job":"fluentd"}
        url "http://${var.loki_distributor_name}.${var.loki_distributor_namespace}.svc.cluster.local:${var.loki_distributor_port}"
      </match>

      # Container logs
      <source>
        @type tail
        @id container_logs
        path /var/log/containers/*.log
        exclude_path [
          "/var/log/containers/fluentd*.log"
        ]
        pos_file /var/log/fluentd-container-logs.log.pos
        tag kubernetes.*
        # Example format:
        #     2025-04-17T06:32:33.354450456-07:00 stderr F ts=2025-04-17T13:32:33.349Z caller=main.go:181 level=info msg="Starting Alertmanager" version="(version=0.27.0, branch=HEAD, revision=0aa3c2aad14cff039931923ab16b26b7481783b5)"
        <parse>
          @type regexp
          # Regex Breakdown:
          # ^                                                                # Anchor to start of line
          # (?<time>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[-+]\d{2}:\d{2}) # Capture timestamp with nanoseconds and timezone
          # \s+                                                              # Match space(s)
          # (?<stream>stdout|stderr)                                         # Capture stream name
          # \s+                                                              # Match space(s)
          # (?<log_flags>[FP])                                               # Capture Docker log flag (F=Full, P=Partial)
          # \s+                                                              # Match space(s)
          # (?<message>.*)                                                   # Capture the message greedily
          # $                                                                # Anchor to end of line
          expression /^(?<time>[^ ]+)\s+(?<stream>[^ ]+)\s+(?<log_flags>[^ ]+)\s+(?<message>.*)$/
          time_key time
          time_format %Y-%m-%dT%H:%M:%S.%N%:z
          keep_time_key true
          # Define data types for captured fields (optional but recommended)
          types stream:string, log_flags:string, message:string
        </parse>
      </source>
      <filter kubernetes.**>
        @type kubernetes_metadata
        @id filter_kube_metadata
      </filter>
      <match kubernetes.**>
        @type loki
        <buffer>
          flush_interval 10s
          flush_at_shutdown true
        </buffer>
        extra_labels {"env":"${var.env_name}","job":"fluentd"}
        extract_kubernetes_labels true
        <label>
          container $.kubernetes.container_name
        </label>
        <label>
          container_image $.kubernetes.container_image
        </label>
        <label>
          namespace $.kubernetes.namespace_name
        </label>
        <label>
          pod $.kubernetes.pod_name
        </label>
        remove_keys docker, kubernetes
        url "http://${var.loki_distributor_name}.${var.loki_distributor_namespace}.svc.cluster.local:${var.loki_distributor_port}"
      </match>
    EOF
  }
}

resource "kubernetes_service_account" "fluentd" {
  metadata {
    name      = "fluentd"
    namespace = var.namespace_name
  }
}

resource "kubernetes_cluster_role" "fluentd" {
  metadata {
    name = "fluentd"
  }
  rule {
    api_groups = [""]
    resources = [
      "namespaces",
      "pods",
    ]
    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "fluentd" {
  metadata {
    name = "fluentd"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.fluentd.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "fluentd"
    namespace = var.namespace_name
  }
}

# Based on https://github.com/fluent/fluentd-kubernetes-daemonset/blob/master/fluentd-daemonset-forward.yaml
resource "kubernetes_daemonset" "fluentd" {
  metadata {
    labels = {
      app     = "fluentd"
      version = "v${var.fluentd_version}"
    }
    name      = "fluentd"
    namespace = var.namespace_name
  }
  spec {
    selector {
      match_labels = {
        app     = "fluentd"
        version = "v${var.fluentd_version}"
      }
    }
    template {
      metadata {
        labels = {
          app     = "fluentd"
          version = "v${var.fluentd_version}"
        }
      }
      spec {
        container {
          command = [
            "/bin/sh",
            "-eu",
            "-c",
            <<-EOF
              fluent-gem i fluent-plugin-grafana-loki
              # Call the container image's default entrypoint.
              tini -s -- /fluentd/entrypoint.sh
            EOF
          ]
          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          image = "fluent/fluentd-kubernetes-daemonset:v${var.fluentd_version}-debian-forward-1"
          name  = "fluentd"
          resources {
            limits = {
              memory = "200Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "200Mi"
            }
          }
          volume_mount {
            mount_path = "/fluentd/etc"
            name       = "config"
            read_only  = true
          }
          volume_mount {
            name       = "nodelogs"
            mount_path = "/var/log"
            read_only  = false
          }
          volume_mount {
            mount_path = "/var/log/pods"
            name       = "podlogs"
            read_only  = true
          }
        }
        service_account_name             = kubernetes_service_account.fluentd.metadata[0].name
        termination_grace_period_seconds = 30
        toleration {
          key    = "node-role.kubernetes.io/control-plane"
          effect = "NoSchedule"
        }
        toleration {
          key    = "node-role.kubernetes.io/master"
          effect = "NoSchedule"
        }
        volume {
          config_map {
            name = kubernetes_config_map.fluentd.metadata[0].name
          }
          name = "config"
        }
        volume {
          host_path {
            path = "/var/log"
          }
          name = "nodelogs"
        }
        volume {
          host_path {
            path = "/var/log/pods"
          }
          name = "podlogs"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "vpa" {
  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      namespace = var.namespace_name
      name      = "fluentd"
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "DaemonSet"
        name       = kubernetes_daemonset.fluentd.metadata[0].name
      }
      updatePolicy = {
        updateMode = "Off"
      }
    }
  }
}

resource "kubernetes_network_policy" "fluentd_egress_to_loki" {
  metadata {
    name      = "fluentd-egress-to-loki"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_labels = kubernetes_daemonset.fluentd.metadata[0].labels
    }
    policy_types = [
      "Egress"
    ]
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = var.namespace_name
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/component" = "distributor"
            "app.kubernetes.io/instance"  = "loki"
          }
        }
      }
      ports {
        port     = var.loki_distributor_port
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "loki_ingress_from_fluentd" {
  metadata {
    name      = "loki-ingress-from-fluentd"
    namespace = var.loki_distributor_namespace
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "distributor"
        "app.kubernetes.io/instance"  = "loki"
      }
    }
    policy_types = [
      "Ingress"
    ]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = var.namespace_name
          }
        }
        pod_selector {
          match_labels = kubernetes_daemonset.fluentd.metadata[0].labels
        }
      }
      ports {
        port     = var.loki_distributor_port
        protocol = "TCP"
      }
    }
  }
}
