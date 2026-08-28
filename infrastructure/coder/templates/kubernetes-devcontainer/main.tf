terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "coder" {}

# The Coder provisioner runs in the cluster and authenticates with the Coder
# ServiceAccount. Its Role is scoped to coder-workspaces by the Helm release.
provider "kubernetes" {}

data "coder_provisioner" "current" {}
data "coder_workspace" "current" {}
data "coder_workspace_owner" "current" {}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Maximum CPU cores available to the workspace."
  type         = "number"
  default      = "4"
  mutable      = true
  order        = 1

  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "Maximum memory available to the workspace, in GiB."
  type         = "number"
  default      = "8"
  mutable      = true
  order        = 2

  validation {
    min = 2
    max = 32
  }
}

data "coder_parameter" "workspace_volume_size" {
  name         = "workspace_volume_size"
  display_name = "Workspace volume"
  description  = "Persistent /workspaces volume size, in GiB."
  type         = "number"
  default      = "30"
  mutable      = false
  order        = 3

  validation {
    min = 10
    max = 250
  }
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Git repository"
  description  = "Git URL containing .devcontainer/devcontainer.json. Use SSH for private repositories."
  type         = "string"
  mutable      = false
  order        = 4
}

data "coder_parameter" "workspace_folder" {
  name         = "workspace_folder"
  display_name = "Workspace folder"
  description  = "Absolute path where Envbuilder clones the repository and mounts persistent storage."
  type         = "string"
  default      = "/workspaces/project"
  mutable      = false
  order        = 5
}

data "coder_parameter" "dockerfile_path" {
  name         = "dockerfile_path"
  display_name = "Dockerfile path"
  description  = "Optional repository-relative Dockerfile. Use this when the devcontainer is Compose-based."
  type         = "string"
  default      = ""
  mutable      = false
  order        = 6
}

data "coder_parameter" "service_port" {
  name         = "service_port"
  display_name = "Application port"
  description  = "Port exposed to the other Coder workspaces through a stable ClusterIP Service."
  type         = "number"
  default      = "3000"
  mutable      = true
  order        = 7

  validation {
    min = 1
    max = 65535
  }
}

data "coder_parameter" "fallback_image" {
  name         = "fallback_image"
  display_name = "Fallback image"
  description  = "Image used to make the workspace reachable when the devcontainer build fails."
  type         = "string"
  default      = "codercom/enterprise-base:ubuntu"
  mutable      = true
  order        = 8
}

locals {
  namespace        = "coder-workspaces"
  storage_class    = "longhorn-coder-workspaces"
  coder_agent_url  = "http://coder.coder-system.svc.cluster.local"
  envbuilder_image = "ghcr.io/coder/envbuilder:1.3.0"
  workspace_id     = lower(data.coder_workspace.current.id)
  deployment_name  = "coder-${local.workspace_id}"
  owner_name       = replace(lower(data.coder_workspace_owner.current.name), "/[^a-z0-9-]/", "-")
  workspace_name   = replace(lower(data.coder_workspace.current.name), "/[^a-z0-9-]/", "-")
  service_name     = substr("coder-${local.owner_name}-${local.workspace_name}", 0, 63)
  service_dns      = "${local.service_name}.${local.namespace}.svc.cluster.local"
  git_author_name  = coalesce(data.coder_workspace_owner.current.full_name, data.coder_workspace_owner.current.name)
  git_author_email = data.coder_workspace_owner.current.email
  rewritten_agent_init_script = replace(
    coder_agent.main.init_script,
    data.coder_workspace.current.access_url,
    local.coder_agent_url,
  )
  workspace_labels = {
    "app.kubernetes.io/name"     = "coder-workspace"
    "app.kubernetes.io/instance" = local.deployment_name
    "app.kubernetes.io/part-of"  = "coder"
    "com.coder.resource"         = "true"
    "com.coder.workspace.id"     = data.coder_workspace.current.id
    "com.coder.workspace.name"   = data.coder_workspace.current.name
    "com.coder.user.id"          = data.coder_workspace_owner.current.id
    "com.coder.user.username"    = data.coder_workspace_owner.current.name
  }
  envbuilder_env = {
    CODER_AGENT_TOKEN                     = coder_agent.main.token
    CODER_AGENT_URL                       = local.coder_agent_url
    ENVBUILDER_DOCKERFILE_PATH            = data.coder_parameter.dockerfile_path.value
    ENVBUILDER_EXIT_ON_BUILD_FAILURE      = "true"
    ENVBUILDER_FALLBACK_IMAGE             = data.coder_parameter.fallback_image.value
    ENVBUILDER_GIT_SSH_PRIVATE_KEY_BASE64 = base64encode(try(data.coder_workspace_owner.current.ssh_private_key, ""))
    ENVBUILDER_GIT_URL                    = data.coder_parameter.repo.value
    ENVBUILDER_INIT_SCRIPT                = local.rewritten_agent_init_script
    ENVBUILDER_WORKSPACE_FOLDER           = data.coder_parameter.workspace_folder.value
  }
}

resource "kubernetes_persistent_volume_claim_v1" "workspaces" {
  metadata {
    name      = "${local.deployment_name}-workspaces"
    namespace = local.namespace
    labels    = local.workspace_labels
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.current.email
    }
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = local.storage_class

    resources {
      requests = {
        storage = "${data.coder_parameter.workspace_volume_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "workspace" {
  count = data.coder_workspace.current.start_count

  depends_on = [kubernetes_persistent_volume_claim_v1.workspaces]

  wait_for_rollout = false

  metadata {
    name      = local.deployment_name
    namespace = local.namespace
    labels    = local.workspace_labels
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.current.email
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/instance" = local.deployment_name
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = local.workspace_labels
      }

      spec {
        automount_service_account_token  = false
        termination_grace_period_seconds = 30

        container {
          name              = "dev"
          image             = local.envbuilder_image
          image_pull_policy = "IfNotPresent"

          dynamic "env" {
            for_each = nonsensitive(local.envbuilder_env)
            content {
              name  = env.key
              value = env.value
            }
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = data.coder_parameter.cpu.value
              memory = "${data.coder_parameter.memory.value}Gi"
            }
          }

          volume_mount {
            name       = "workspaces"
            mount_path = data.coder_parameter.workspace_folder.value
            read_only  = false
          }
        }

        volume {
          name = "workspaces"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.workspaces.metadata[0].name
            read_only  = false
          }
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1

              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"

                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# This Service remains while the workspace is stopped, so its DNS name is
# stable. It has no endpoints until the workspace Deployment is started.
resource "kubernetes_service_v1" "workspace" {
  metadata {
    name      = local.service_name
    namespace = local.namespace
    labels    = local.workspace_labels
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.current.email
    }
  }

  spec {
    type = "ClusterIP"
    selector = {
      "app.kubernetes.io/instance" = local.deployment_name
    }

    port {
      name        = "app"
      port        = tonumber(data.coder_parameter.service_port.value)
      target_port = tostring(data.coder_parameter.service_port.value)
      protocol    = "TCP"
    }
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.current.arch
  os   = "linux"

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
  }

  metadata {
    display_name = "CPU usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory usage"
    key          = "1_memory_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Workspace disk"
    key          = "2_workspace_disk"
    script       = "coder stat disk --path ${data.coder_parameter.workspace_folder.value}"
    interval     = 60
    timeout      = 1
  }
}

resource "coder_metadata" "workspace" {
  count       = data.coder_workspace.current.start_count
  resource_id = coder_agent.main.id

  item {
    key   = "repository"
    value = data.coder_parameter.repo.value
  }

  item {
    key   = "workspace folder"
    value = data.coder_parameter.workspace_folder.value
  }

  item {
    key   = "build source"
    value = data.coder_parameter.dockerfile_path.value == "" ? ".devcontainer/devcontainer.json" : data.coder_parameter.dockerfile_path.value
  }

  item {
    key   = "internal service"
    value = "http://${local.service_dns}:${data.coder_parameter.service_port.value}"
  }

  item {
    key   = "workspace image builder"
    value = local.envbuilder_image
  }
}
