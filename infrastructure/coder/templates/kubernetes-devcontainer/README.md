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
- Coder SSH access for tmux and Neovim.

The repository has a stable path configured by the `workspace_folder`
parameter, which defaults to `/workspaces/project`.

Envbuilder does not support Compose-based devcontainers. For those repositories,
set `dockerfile_path` to the repository's development Dockerfile and set
`workspace_folder` to the path expected by that image. Leaving
`dockerfile_path` empty uses `.devcontainer/devcontainer.json` directly.
Clone and build failures stop the workspace instead of starting an unrelated
fallback image.

Neovim and tmux should be installed by the repository's devcontainer image or
features. This template deliberately does not install a browser IDE.

For private repositories, use the SSH clone URL and register the SSH public key
shown in the Coder account settings with the Git provider.

The application must listen on `0.0.0.0` and on the configured application
port to be reachable from another workspace. A backend workspace named
`backend-dev`, owned by `TiborSuty`, is reachable inside the cluster at:

```text
http://coder-tiborsuty-backend-dev.coder-workspaces.svc.cluster.local:<port>
```

Stopping a workspace removes its Deployment but preserves its Service and PVC.
Deleting a workspace removes those resources and the dedicated StorageClass
deletes the corresponding Longhorn volume.
