---
display_name: Kubernetes Devcontainer
description: Run one repository's devcontainer as a persistent Coder workspace
tags: [kubernetes, devcontainer, neovim]
---

# Kubernetes devcontainer workspace

This template creates one Coder workspace per Git repository. Envbuilder reads
the repository's `.devcontainer/devcontainer.json` and turns it into the
workspace container without requiring Docker or a privileged Pod.

Each workspace gets:

- an ephemeral Deployment in `coder-workspaces`;
- a persistent Longhorn volume mounted at `/workspaces`;
- a stable ClusterIP Service for communication with other workspaces;
- an authenticated subdomain application proxy for the configured port;
- a pinned Bitwarden CLI configured for the private Vaultwarden service;
- personal Neovim, tmux, Git, Starship, and Vaultwarden CA configuration
  applied from `TiborSuty/dotfiles` with GNU Stow;
- Coder SSH access for tmux and Neovim.

The **Frontend DMS** workspace preset fills the frontend repository, resource,
Dockerfile, application, and startup parameters. An init container stages the
pre-created `coder-workspaces/coder-frontend-dms-environment` Secret in the
persistent workspace with mode `600`; it is copied into `apps/dms/.env` and the
staged copy is removed when the application starts. The preset installs
dependencies when `node_modules/.bin/nx` is absent and starts DMS on port
`4300`. Create the Secret with
`bootstrap/create-coder-frontend-env-secret.sh`; never place the environment
contents in this template or in a Coder parameter.

The repository has a stable path configured by the `workspace_folder`
parameter, which defaults to `/workspaces/project`.

Envbuilder does not support Compose-based devcontainers. For those repositories,
set `dockerfile_path` to the repository's development Dockerfile and set
`workspace_folder` to the path expected by that image. Leaving
`dockerfile_path` empty uses `.devcontainer/devcontainer.json` directly.
Clone and build failures stop the workspace instead of starting an unrelated
fallback image.

Neovim and tmux should be installed by the repository's devcontainer image or
features. This template deliberately does not install a browser IDE. A
checksum-verified init container installs the Bitwarden CLI and GNU Stow, and
copies the public internal Vaultwarden CA into the persistent workspace before
Envbuilder starts. The dev container mounts only that workspace volume,
avoiding unsupported Envbuilder remounts of auxiliary Kubernetes volumes.
Users still log in and unlock interactively; no vault credentials or session
keys are stored in the template.

The template stages checksum-pinned GNU Stow 2.4.1 in the persistent workspace
and adds it to the agent's `PATH`; the devcontainer image only needs the Perl
runtime used by Stow. The pinned Coder dotfiles module then clones the public
dotfiles repository and runs its executable `install.sh`. That installer uses
an explicit allowlist, so macOS-only files and secret-bearing local state are
not linked into the Linux workspace. The module also adds a **Refresh
Dotfiles** button to each running workspace.

For private repositories, use the SSH clone URL and register the SSH public key
shown in the Coder account settings with the Git provider.

The application must listen on `0.0.0.0` and on the configured application
port to be reachable from another workspace. A backend workspace named
`backend-dev`, owned by `TiborSuty`, is reachable inside the cluster at:

```text
http://coder-tiborsuty-backend-dev.coder-workspaces.svc.cluster.local:<port>
```

Set `application_start_command` to start an application automatically whenever
the Coder agent starts. The command runs from `workspace_folder` in the
background, writes application output to `/tmp/coder-application.log`, and does
not block terminal access. Leave it empty when the application should be
started manually. The dashboard link remains owner-only and uses a unique Coder
subdomain, so frontend assets and development-server WebSockets can use paths
relative to `/`.

Stopping a workspace removes its Deployment but preserves its Service and PVC.
Deleting a workspace removes those resources and the dedicated StorageClass
deletes the corresponding Longhorn volume.
