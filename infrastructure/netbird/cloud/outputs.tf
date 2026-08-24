output "homepage_reverse_proxy_url" {
  description = "Public HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.homepage.domain}"
}

output "grafana_reverse_proxy_url" {
  description = "Public Grafana HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.grafana.domain}"
}
