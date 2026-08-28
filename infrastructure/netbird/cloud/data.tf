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

data "netbird_network_resource" "coder" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.coder_resource_id
}

data "netbird_network_resource" "grafana" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.grafana_resource_id
}

data "netbird_network_resource" "argocd" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.argocd_resource_id
}

data "netbird_network_resource" "longhorn" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.longhorn_resource_id
}

data "netbird_network_resource" "hubble" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.hubble_resource_id
}

data "netbird_network_resource" "prometheus" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.prometheus_resource_id
}

data "netbird_network_resource" "alertmanager" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.alertmanager_resource_id
}

data "netbird_network_resource" "minio" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.minio_resource_id
}

data "netbird_reverse_proxy_domain" "free" {
  type = "free"
}
