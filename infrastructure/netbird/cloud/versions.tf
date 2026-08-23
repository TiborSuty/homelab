terraform {
  required_version = ">= 1.15.0, < 2.0.0"

  backend "kubernetes" {
    namespace     = "netbird"
    secret_suffix = "netbird-cloud"
    labels = {
      "app.kubernetes.io/name"       = "netbird-cloud"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "0.0.9"
    }
  }
}
