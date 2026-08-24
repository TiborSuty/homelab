output "homepage_reverse_proxy_url" {
  description = "Public HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.homepage.domain}"
}

output "grafana_reverse_proxy_url" {
  description = "Public Grafana HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.grafana.domain}"
}

output "argocd_reverse_proxy_url" {
  description = "Public Argo CD HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.argocd.domain}"
}

output "longhorn_reverse_proxy_url" {
  description = "Public Longhorn HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.longhorn.domain}"
}

output "hubble_reverse_proxy_url" {
  description = "Public Hubble HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.hubble.domain}"
}

output "prometheus_reverse_proxy_url" {
  description = "Public Prometheus HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.prometheus.domain}"
}

output "alertmanager_reverse_proxy_url" {
  description = "Public Alertmanager HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.alertmanager.domain}"
}

output "minio_reverse_proxy_url" {
  description = "Public MinIO HTTPS entry point protected by NetBird account SSO."
  value       = "https://${netbird_reverse_proxy_service.minio.domain}"
}
