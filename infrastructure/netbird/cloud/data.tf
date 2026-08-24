data "netbird_network" "homelab_services" {
  name = "homelab-services"
}

data "netbird_group" "dashboard_clients" {
  name = "dashboard-clients"
}

data "netbird_group" "dashboard_services" {
  name = "dashboard-services"
}

# The Kubernetes operator owns these network resources. Their NetBird resource
# IDs are stable for the lifetime of the corresponding Kubernetes objects.
data "netbird_network_resource" "homepage" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.homepage_resource_id
}

data "netbird_network_resource" "grafana" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.grafana_resource_id
}

data "netbird_reverse_proxy_domain" "free" {
  type = "free"
}
