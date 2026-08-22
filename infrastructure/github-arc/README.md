# GitHub Actions Runner Controller

GitHub ARC `0.14.2` provides ephemeral self-hosted runners for
`TiborSuty/homelab`. The controller and listener run in `arc-systems`; runner
scale-set resources and job runners run in the separate `arc-runners`
namespace.

The runner scale set is named `homelab-runners`, scales from zero to at most two
concurrent runners, and does not enable Docker-in-Docker. Each job receives a
fresh runner Pod with ephemeral working storage. Runner Pods do not receive a
Kubernetes ServiceAccount token.

## Authentication

The runner chart references the existing Secret
`arc-runners/github-arc-auth`. Create it before enabling the runner application:

```sh
./bootstrap/create-github-arc-secret.sh
```

The helper prompts for the token without echoing it and does not write it to
disk or to the repository. Create a dedicated fine-grained personal access
token, limit it to the `homelab` repository, and grant
`Administration: Read and write`. For non-interactive use, provide it through
`GITHUB_ARC_TOKEN`. The Secret can be rotated with `GITHUB_ARC_ROTATE=1`.

## Workflows

Target the scale set by using:

```yaml
runs-on: homelab-runners
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
configuration. The current scale set is deliberately unprivileged.
