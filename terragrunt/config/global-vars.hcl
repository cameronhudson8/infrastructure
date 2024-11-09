locals {
  kube_prometheus_version = "v0.14.0"
  monitoring_emails = {
    recipient = {
      email_address = "cameronhudson8@gmail.com"
    }
    sender = {
      transport = "smtp.zoho.com:587"
    }
  }
  monitoring_namespace_name = "monitoring"
  vpa_namespace_name        = "vpa-operator"
  vpa_operator_version      = "1.2.0"
}
