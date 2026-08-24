variable "homepage_resource_id" {
  description = "NetBird resource ID reported by the Homepage NetworkResource status."
  type        = string
  default     = "da5kpgafadhs73d338r0"

  validation {
    condition     = length(var.homepage_resource_id) > 0
    error_message = "homepage_resource_id must not be empty."
  }
}

variable "grafana_resource_id" {
  description = "NetBird resource ID reported by the Grafana NetworkResource status."
  type        = string
  default     = "da67c33l0ubs73c7p0og"

  validation {
    condition     = length(var.grafana_resource_id) > 0
    error_message = "grafana_resource_id must not be empty."
  }
}

variable "argocd_resource_id" {
  description = "NetBird resource ID reported by the Argo CD NetworkResource status."
  type        = string
  default     = "da67iuqfadhs73fce470"

  validation {
    condition     = length(var.argocd_resource_id) > 0
    error_message = "argocd_resource_id must not be empty."
  }
}

variable "longhorn_resource_id" {
  description = "NetBird resource ID reported by the Longhorn NetworkResource status."
  type        = string
  default     = "da67iuqfadhs73fce5ig"

  validation {
    condition     = length(var.longhorn_resource_id) > 0
    error_message = "longhorn_resource_id must not be empty."
  }
}

variable "hubble_resource_id" {
  description = "NetBird resource ID reported by the Hubble NetworkResource status."
  type        = string
  default     = "da67iurl0ubs73ccnk50"

  validation {
    condition     = length(var.hubble_resource_id) > 0
    error_message = "hubble_resource_id must not be empty."
  }
}

variable "prometheus_resource_id" {
  description = "NetBird resource ID reported by the Prometheus NetworkResource status."
  type        = string
  default     = "da67iv3l0ubs73ccnnl0"

  validation {
    condition     = length(var.prometheus_resource_id) > 0
    error_message = "prometheus_resource_id must not be empty."
  }
}

variable "alertmanager_resource_id" {
  description = "NetBird resource ID reported by the Alertmanager NetworkResource status."
  type        = string
  default     = "da67iuifadhs73fce330"

  validation {
    condition     = length(var.alertmanager_resource_id) > 0
    error_message = "alertmanager_resource_id must not be empty."
  }
}

variable "minio_resource_id" {
  description = "NetBird resource ID reported by the MinIO NetworkResource status."
  type        = string
  default     = "da67iurl0ubs73ccnlvg"

  validation {
    condition     = length(var.minio_resource_id) > 0
    error_message = "minio_resource_id must not be empty."
  }
}
