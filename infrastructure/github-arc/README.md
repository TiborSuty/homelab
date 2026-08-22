# GitHub Actions Runner Controller

GitHub ARC `0.14.2` provides ephemeral self-hosted runners for these repositories:

- `TiborSuty/homelab` uses `homelab-runners` in `arc-runners`.
- `TiborSuty/loky-planner` uses `loky-planner-runners` in `arc-loky-planner`.

The shared controller runs in `arc-systems`. Each runner scale set scales from
zero to at most two concurrent runners and does not enable Docker-in-Docker.
Each job receives a fresh runner Pod with ephemeral working storage. Runner Pods
do not receive a Kubernetes ServiceAccount token.

The shared controller exposes Prometheus metrics for itself and all runner-set
listeners on port `8080` at `/metrics`. The monitoring stack discovers these
Pods through its `github-arc` PodMonitor.

## Authentication

Each runner chart references a repository-specific Secret. Create the homelab
Secret before enabling its runner application:

```sh
./bootstrap/create-github-arc-secret.sh
```

The helper prompts for the token without echoing it and does not write it to
disk or to the repository. Create a dedicated fine-grained personal access
token, limit it to the `homelab` repository, and grant
`Administration: Read and write`. For non-interactive use, provide it through
`GITHUB_ARC_TOKEN`. The Secret can be rotated with `GITHUB_ARC_ROTATE=1`.

Create the `loky-planner` Secret with its dedicated token before enabling that
runner application:

```sh
GITHUB_ARC_NAMESPACE=arc-loky-planner \
GITHUB_ARC_SECRET_NAME=github-arc-loky-planner-auth \
  ./bootstrap/create-github-arc-secret.sh
```

## Workflows

Target the scale set by using:

```yaml
runs-on: homelab-runners
```

Workflows in `TiborSuty/loky-planner` use:

```yaml
runs-on: loky-planner-runners
```

The included `ARC smoke test` workflow is manual. Trigger it with:

```sh
gh workflow run arc-smoke-test.yaml
```

Observe the ephemeral runner while the job is active:

```sh
KUBECONFIG="$PWD/.local/kubeconfig" \
  kubectl -n arc-runners get pods -w
```

Jobs that require Docker builds need a separate, explicitly reviewed runner
configuration. The current scale sets are deliberately unprivileged.
