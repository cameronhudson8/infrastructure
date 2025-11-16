# # Need to build a sidecar that will:
# # 1. Be able to determine where it left off
# # 1. Watch the change log
# # 1. Send events to Kafka
# # 1. Update its checkpoint / offset
# resource "container?" "cassandra_change_event_exporter" {
# }

resource "kubernetes_stateful_set" "cassandra" {
  metadata {
    name      = "cassandra"
    namespace = "application"
  }
  spec {
    selector {
      match_labels = {
        app = "cassandra"
      }
    }
    template {
      metadata {
        name      = "cassandra"
        namespace = "application"
      }
      spec {
        container {
          image = "docker.io/cassandra:${var.cassandra_version}"
          name  = "cassandra"
        }
      }
    }
    service_name = "cassandra"
  }
}
