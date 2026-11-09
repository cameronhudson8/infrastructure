resource "kubernetes_network_policy_v1" "allow_mimir_jobs_egress_to_mimir_minio" {
  metadata {
    name      = "allow-mimir-bucket-creator-egress-to-mimir-minio"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app"
        operator = "In"
        values = [
          "mimir-distributed-job",
          "minio-job",
        ]
      }
      match_labels = {
        release = "mimir-distributed"
      }
    }
    policy_types = ["Egress"]
    egress {
      to {
        pod_selector {
          match_labels = {
            app     = "minio"
            release = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9000
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_minio_ingress_from_mimir_jobs" {
  metadata {
    name      = "allow-mimir-minio-ingress-from-mimir-bucket-creator"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_labels = {
        app     = "minio"
        release = "mimir-distributed"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_expressions {
            key      = "app"
            operator = "In"
            values = [
              "mimir-distributed-job",
              "minio-job",
            ]
          }
          match_labels = {
            release = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9000
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_pods_egress_to_mimir_minio" {
  metadata {
    name      = "allow-mimir-pods-egress-to-mimir-minio"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/component"
        operator = "In"
        values = [
          "alertmanager",
          "compactor",
          "ingester",
          "querier",
          "ruler",
          "store-gateway",
        ]
      }
      match_labels = {
        "app.kubernetes.io/instance" = "mimir-distributed"
      }
    }
    policy_types = ["Egress"]
    egress {
      to {
        pod_selector {
          match_labels = {
            app     = "minio"
            release = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9000
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_minio_ingress_from_mimir_pods" {
  metadata {
    name      = "allow-mimir-minio-ingress-from-mimir-pods"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_labels = {
        app     = "minio"
        release = "mimir-distributed"
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_expressions {
            key      = "app.kubernetes.io/component"
            operator = "In"
            values = [
              "alertmanager",
              "compactor",
              "ingester",
              "querier",
              "ruler",
              "store-gateway",
            ]
          }
          match_labels = {
            "app.kubernetes.io/instance" = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9000
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_pods_egress_to_and_ingress_from_mimir_pods" {
  metadata {
    name      = "allow-mimir-pods-egress-to-and-ingress-from-mimir-pods"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/component"
        operator = "In"
        values = [
          "alertmanager",
          "compactor",
          "distributor",
          "ingester",
          "querier",
          "ruler",
          "store-gateway",
        ]
      }
      match_labels = {
        "app.kubernetes.io/instance" = "mimir-distributed"
      }
    }
    policy_types = [
      "Egress",
      "Ingress",
    ]
    egress {
      to {
        pod_selector {
          match_expressions {
            key      = "app.kubernetes.io/component"
            operator = "In"
            values = [
              "alertmanager",
              "compactor",
              "distributor",
              "ingester",
              "querier",
              "ruler",
              "store-gateway",
            ]
          }
          match_labels = {
            "app.kubernetes.io/instance" = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 7946
        protocol = "TCP"
      }
    }
    ingress {
      from {
        pod_selector {
          match_expressions {
            key      = "app.kubernetes.io/component"
            operator = "In"
            values = [
              "alertmanager",
              "compactor",
              "distributor",
              "ingester",
              "querier",
              "ruler",
              "store-gateway",
            ]
          }
          match_labels = {
            "app.kubernetes.io/instance" = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 7946
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_pods_egress_to_mimir_kafka" {
  metadata {
    name      = "allow-mimir-pods-egress-to-mimir-kafka"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_expressions {
        key      = "app.kubernetes.io/component"
        operator = "In"
        values = [
          "distributor",
          "ingester",
          "ruler",
        ]
      }
      match_labels = {
        "app.kubernetes.io/instance" = "mimir-distributed"
      }
    }
    policy_types = ["Egress"]
    egress {
      to {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/component" = "kafka"
            "app.kubernetes.io/instance"  = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9092
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_mimir_kafka_ingress_from_mimir_pods" {
  metadata {
    name      = "allow-mimir-kafka-ingress-from-mimir-pods"
    namespace = var.namespace_name
  }
  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/component" = "kafka"
        "app.kubernetes.io/instance"  = "mimir-distributed"
      }

    }
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {
          match_expressions {
            key      = "app.kubernetes.io/component"
            operator = "In"
            values = [
              "distributor",
              "ingester",
              "ruler",
            ]
          }
          match_labels = {
            "app.kubernetes.io/instance" = "mimir-distributed"
          }
        }
      }
      ports {
        port     = 9092
        protocol = "TCP"
      }
    }
  }
}

resource "helm_release" "mimir" {
  atomic = true
  chart  = "mimir-distributed"
  depends_on = [
    kubernetes_network_policy_v1.allow_mimir_jobs_egress_to_mimir_minio,
    kubernetes_network_policy_v1.allow_mimir_kafka_ingress_from_mimir_pods,
    kubernetes_network_policy_v1.allow_mimir_minio_ingress_from_mimir_jobs,
    kubernetes_network_policy_v1.allow_mimir_minio_ingress_from_mimir_pods,
    kubernetes_network_policy_v1.allow_mimir_pods_egress_to_and_ingress_from_mimir_pods,
    kubernetes_network_policy_v1.allow_mimir_pods_egress_to_mimir_kafka,
    kubernetes_network_policy_v1.allow_mimir_pods_egress_to_mimir_minio,
  ]
  name       = "mimir-distributed"
  namespace  = var.namespace_name
  repository = "https://grafana.github.io/helm-charts"
  values = [
    yamlencode({
      alertmanager = {
        persistentVolume = {
          storageClass = "standard-rwo"
        }
      }
      compactor = {
        persistentVolume = {
          storageClass = "standard-rwo"
        }
      }
      ingester = {
        persistentVolume = {
          storageClass = "standard-rwo"
        }
        zoneAwareReplication = {
          enabled = true
        }
      }
      minio = {
        persistence = {
          storageClass = "standard-rwo"
        }
      }
      store_gateway = {
        persistentVolume = {
          storageClass = "standard-rwo"
        }
        zoneAwareReplication = {
          enabled = true
        }
      }
    })
  ]
  version = var.helm_chart_version
}
