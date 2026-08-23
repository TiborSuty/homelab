variable "homepage_resource_id" {
  description = "NetBird resource ID reported by the Homepage NetworkResource status."
  type        = string
  default     = "da5kpgafadhs73d338r0"

  validation {
    condition     = length(var.homepage_resource_id) > 0
    error_message = "homepage_resource_id must not be empty."
  }
}
