# IPv4 CIDR block calculations
#
# Address Range                     |               CIDR |  Final Address | Address Count
# --------------------------------- | ------------------ | -------------- | -------------
# ++ Secondary Range 1 (Pods)       |         10.0.0.0/9 | 10.127.255.255 | 2 ^ 23
# ++ Kubernetes Pods                |                  - | 10.127.255.253 | 2 ^ 23 - 2
# ++ (Reserved) "For future use"    |  10.127.255.254/32 | 10.127.255.254 | 2 ^ 0
# ++ (Reserved) "Broadcast address" |  10.127.255.255/32 | 10.127.255.255 | 2 ^ 0

# I currently only have 1 GCP project. Reconsider later.
gcp_project_id                   = "cameronhudson8"
gcp_region                       = "us-central1"
ingress_nginx_helm_chart_version = "4.12.0"
ingress_nginx_service_type       = "LoadBalancer"
kube_prometheus_version          = "v0.14.0"
# kubernetes_control_plane_ipv4_cidr = "10.255.255.224/28"
kubernetes_control_plane_ipv4_cidr = "172.16.0.16/28"
# kubernetes_nodes_ipv4_cidr         = "10.192.0.0/11"
kubernetes_nodes_ipv4_cidr = "192.168.0.0/20"
# kubernetes_pods_ipv4_cidr          = "10.0.0.0/9"
kubernetes_pods_ipv4_cidr = "10.4.0.0/14"
# kubernetes_services_ipv4_cidr = "10.128.0.0/10"
kubernetes_services_ipv4_cidr = "10.0.32.0/20"
kubernetes_version            = "1.30"
# "e2-standard-2" costs less per CPU and per GB mem, but the smallest size is twice as large as "t2a-standard-1".
# on_demand_node_machine_type      = "t2a-standard-1"
on_demand_node_machine_type = "e2-small"
tf_state_bucket_name        = "cameronhudson8-prod-tf-state"
vpa_operator_version        = "1.2.0"
