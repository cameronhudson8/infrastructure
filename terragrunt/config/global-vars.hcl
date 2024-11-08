locals {
  kube_prometheus_version    = "v0.14.0"
  kube_state_metrics_version = "v2.13.0"
  metrics_server_version     = "v0.7.2"
  monitoring_email_sender = {
    address       = "monitoring@cameronhudson8.com"
    transport     = "smtp.zoho.com:587"
  }
  monitoring_email_recipient_address    = "cameronhudson8@gmail.com"
  monitoring_namespace_name             = "monitoring"
  prometheus_operator_version           = "v0.75.2"
  vpa_namespace_name                    = "vpa-operator"
  vpa_operator_version                  = "1.2.1"
}
