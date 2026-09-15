variable "loky_planner_resource_id" {
  description = "NetBird resource ID reported by Loky Planner's NetworkResource status."
  type        = string
  default     = "dakojhafadhs73fp48n0"
}

data "netbird_network_resource" "loky_planner" {
  network_id = data.netbird_network.homelab_services.id
  id         = var.loky_planner_resource_id
}

resource "netbird_reverse_proxy_service" "loky_planner" {
  name              = "loky-planner"
  domain            = "tiborsuty-loky-planner.${var.reverse_proxy_domain}"
  enabled           = true
  pass_host_header  = true
  rewrite_redirects = true

  targets = [{
    target_id   = data.netbird_network_resource.loky_planner.id
    target_type = "host"
    port        = 80
    protocol    = "http"
    path        = "/"
    enabled     = true
  }]

  # Loky uses one configured application user. SSO must protect the public edge.
  auth = {
    bearer_auth = {
      enabled = true
    }
  }
}

output "loky_planner_reverse_proxy_url" {
  description = "Loky Planner HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.loky_planner.domain}"
}
