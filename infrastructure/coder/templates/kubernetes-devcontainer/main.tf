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
  description  = "Port where the application listens inside the workspace. The stable ClusterIP Service exposes it on port 80."
  type         = "number"
  default      = "3000"
  mutable      = true
  order        = 7

  validation {
    min = 1
    max = 65535
  }
}

data "coder_parameter" "application_name" {
  name         = "application_name"
  display_name = "Application name"
  description  = "Name shown for the application in the Coder workspace dashboard."
  type         = "string"
  default      = "Application"
  mutable      = true
  order        = 8
}

data "coder_parameter" "application_start_command" {
  name         = "application_start_command"
  display_name = "Application start command"
  description  = "Optional command started automatically from the workspace folder. Leave empty to start the application manually."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 9
}

data "coder_parameter" "workspace_profile" {
  name         = "workspace_profile"
  display_name = "Workspace profile"
  description  = "Selects optional homelab integrations for this workspace."
  type         = "string"
  default      = "generic"
  mutable      = false
  order        = 10

  option {
    name  = "Generic"
    value = "generic"
  }

  option {
    name  = "Frontend DMS"
    value = "frontend-dms"
  }
}

data "coder_workspace_preset" "frontend_dms" {
  name        = "Frontend DMS"
  description = "Frontend monorepo with DMS on port 4300 and automatic first-start setup."
  icon        = "/icon/code.svg"
  default     = true

  parameters = {
    cpu                   = "4"
    memory                = "8"
    workspace_volume_size = "50"
    repo                  = "git@gitlab.eag-group.cloud:teas/frontend-monorepo.git#refs/heads/ts/T20-136929/eag_grid_new_properties"
    workspace_folder      = "/workspace"
    dockerfile_path       = "Dockerfile.dev"
    service_port          = "4300"
    application_name      = "Frontend"
    workspace_profile     = "frontend-dms"
    application_start_command = trimspace(<<-EOT
      install -m 600 .coder-secrets/dms.env apps/dms/.env &&
      rm -f .coder-secrets/dms.env &&
      if [ ! -x node_modules/.bin/nx ]; then
        SKIP_CARAUDIT_POSTINSTALL=true pnpm install --frozen-lockfile;
      fi &&
      exec ./node_modules/.bin/nx serve dms --host=0.0.0.0 --port=4300
    EOT
    )
  }
}

locals {
  namespace                            = "coder-workspaces"
  storage_class                        = "longhorn-coder-workspaces"
  coder_agent_url                      = "http://coder.coder-system.svc.cluster.local"
  envbuilder_image                     = "ghcr.io/coder/envbuilder:1.3.0"
  bitwarden_cli_installer_image        = "alpine:3.22.1@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1"
  vaultwarden_url                      = "https://vaultwarden.vaultwarden.svc.cluster.local"
  vaultwarden_ca_path                  = "${data.coder_parameter.workspace_folder.value}/.coder-tools/share/vaultwarden-ca.crt"
  frontend_dms_environment_enabled     = data.coder_parameter.workspace_profile.value == "frontend-dms"
  frontend_dms_environment_secret_name = "coder-frontend-dms-environment"
  workspace_id                         = lower(data.coder_workspace.current.id)
  deployment_name                      = "coder-${local.workspace_id}"
  owner_name                           = replace(lower(data.coder_workspace_owner.current.name), "/[^a-z0-9-]/", "-")
  workspace_name                       = replace(lower(data.coder_workspace.current.name), "/[^a-z0-9-]/", "-")
  service_name                         = substr("coder-${local.owner_name}-${local.workspace_name}", 0, 63)
  service_dns                          = "${local.service_name}.${local.namespace}.svc.cluster.local"
  git_author_name                      = coalesce(data.coder_workspace_owner.current.full_name, data.coder_workspace_owner.current.name)
  git_author_email                     = data.coder_workspace_owner.current.email
  rewritten_agent_init_script = replace(
    coder_agent.main.init_script,
    data.coder_workspace.current.access_url,
    local.coder_agent_url,
  )
  workspace_init_script = <<-EOT
    #!/usr/bin/env sh
    set -eu

    export PATH="${data.coder_parameter.workspace_folder.value}/.coder-tools/bin:$PATH"

    if ! command -v perl >/dev/null 2>&1; then
      echo "GNU Stow requires Perl, but this workspace image does not provide it." >&2
      exit 1
    fi

    stow --version >/dev/null

    ${local.rewritten_agent_init_script}
  EOT
  workspace_labels = {
    "app.kubernetes.io/name"         = "coder-workspace"
    "app.kubernetes.io/instance"     = local.deployment_name
    "app.kubernetes.io/part-of"      = "coder"
    "com.coder.resource"             = "true"
    "com.coder.workspace.id"         = data.coder_workspace.current.id
    "com.coder.workspace.name"       = data.coder_workspace.current.name
    "com.coder.user.id"              = data.coder_workspace_owner.current.id
    "com.coder.user.username"        = data.coder_workspace_owner.current.name
    "coder.homelab.internal/profile" = data.coder_parameter.workspace_profile.value
  }
  envbuilder_env = {
    CODER_AGENT_TOKEN                     = coder_agent.main.token
    CODER_AGENT_URL                       = local.coder_agent_url
    ENVBUILDER_DOCKERFILE_PATH            = data.coder_parameter.dockerfile_path.value
    ENVBUILDER_EXIT_ON_BUILD_FAILURE      = "true"
    ENVBUILDER_GIT_SSH_PRIVATE_KEY_BASE64 = base64encode(try(data.coder_workspace_owner.current.ssh_private_key, ""))
    ENVBUILDER_GIT_URL                    = data.coder_parameter.repo.value
    ENVBUILDER_INIT_SCRIPT                = local.workspace_init_script
    ENVBUILDER_WORKSPACE_FOLDER           = data.coder_parameter.workspace_folder.value
    NODE_EXTRA_CA_CERTS                   = local.vaultwarden_ca_path
    VAULTWARDEN_URL                       = local.vaultwarden_url
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

        init_container {
          name              = "prepare-coder-workspace"
          image             = local.bitwarden_cli_installer_image
          image_pull_policy = "IfNotPresent"
          command = [
            "/bin/sh",
            "-ec",
            file("${path.module}/scripts/install-bitwarden-cli.sh"),
          ]

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_group               = 0
            run_as_user                = 0

            capabilities {
              add  = ["DAC_OVERRIDE"]
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "workspaces"
            mount_path = "/workspace-volume"
            read_only  = false
          }

          volume_mount {
            name       = "bitwarden-cli-tmp"
            mount_path = "/tmp"
            read_only  = false
          }

          volume_mount {
            name       = "vaultwarden-ca"
            mount_path = "/source/vaultwarden"
            read_only  = true
          }

          dynamic "volume_mount" {
            for_each = local.frontend_dms_environment_enabled ? [1] : []

            content {
              name       = "frontend-dms-environment"
              mount_path = "/source/frontend-dms"
              read_only  = true
            }
          }
        }

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

        volume {
          name = "bitwarden-cli-tmp"

          empty_dir {
            size_limit = "64Mi"
          }
        }

        volume {
          name = "vaultwarden-ca"

          config_map {
            name         = "vaultwarden-ca"
            default_mode = "0444"
          }
        }

        dynamic "volume" {
          for_each = local.frontend_dms_environment_enabled ? [1] : []

          content {
            name = "frontend-dms-environment"

            secret {
              secret_name  = local.frontend_dms_environment_secret_name
              default_mode = "0444"
            }
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
      port        = 80
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
    NODE_EXTRA_CA_CERTS = local.vaultwarden_ca_path
    VAULTWARDEN_URL     = local.vaultwarden_url
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

module "dotfiles" {
  count   = data.coder_workspace.current.start_count
  source  = "registry.coder.com/coder/dotfiles/coder"
  version = "1.4.2"

  agent_id        = coder_agent.main.id
  dotfiles_uri    = "https://github.com/TiborSuty/dotfiles.git"
  dotfiles_branch = "master"
  manual_update   = true
}

resource "coder_script" "application" {
  count = trimspace(data.coder_parameter.application_start_command.value) != "" ? 1 : 0

  agent_id           = coder_agent.main.id
  display_name       = "Start ${data.coder_parameter.application_name.value}"
  icon               = "/icon/terminal.svg"
  log_path           = "/tmp/coder-application-startup.log"
  run_on_start       = true
  start_blocks_login = false
  script = templatefile("${path.module}/scripts/start-application.sh.tftpl", {
    start_command_base64    = base64encode(data.coder_parameter.application_start_command.value)
    workspace_folder_base64 = base64encode(data.coder_parameter.workspace_folder.value)
  })
}

resource "coder_script" "vaultwarden_cli" {
  agent_id           = coder_agent.main.id
  display_name       = "Configure Bitwarden CLI"
  icon               = "/icon/lock.svg"
  log_path           = "/tmp/coder-bitwarden-cli.log"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -eu

    bw config server "$VAULTWARDEN_URL" >/dev/null
  EOT
}

resource "coder_app" "vaultwarden" {
  agent_id     = coder_agent.main.id
  slug         = "vaultwarden"
  display_name = "Vaultwarden"
  url          = "https://vaultwarden.vaultwarden.homelab.internal"
  external     = true
  open_in      = "tab"
  icon         = "/icon/lock.svg"
}

resource "coder_app" "application" {
  agent_id     = coder_agent.main.id
  slug         = "application"
  display_name = data.coder_parameter.application_name.value
  url          = "http://app.${local.workspace_name}.${local.owner_name}.apps.coder.homelab.internal"
  external     = true
  open_in      = "tab"
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
    value = "http://${local.service_dns}"
  }

  item {
    key   = "dashboard application"
    value = data.coder_parameter.application_name.value
  }

  item {
    key   = "workspace image builder"
    value = local.envbuilder_image
  }
}
