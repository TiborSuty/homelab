# Coder

Coder provides the control plane for remote development workspaces. Argo CD
deploys the official Coder Helm chart and a dedicated CloudNativePG database
into the restricted `coder-system` namespace.

- Coder chart and application: `2.36.3`
- PostgreSQL cluster: `coder-postgres`, one PostgreSQL `18.4` instance on
  Longhorn
- PostgreSQL credentials: stored only in the Kubernetes Secret
  `coder-postgres-credentials`; no database password is stored in Git
- Browser exposure: NetBird Cloud HTTPS reverse proxy with account SSO
- Private CLI exposure: NetBird `NetworkResource` backed by the ClusterIP
- Canonical Coder URL: `http://coder.coder-system.homelab.internal`
- Workspace namespace: `coder-workspaces`, enforced at Pod Security baseline
- Workspace permissions: namespace-scoped through the Coder ServiceAccount
- Workspace storage: `longhorn-coder-workspaces` with two replicas and Delete
  reclaim semantics
- Workspace template: `kubernetes-devcontainer`, using Envbuilder `1.3.0`
- Telemetry: disabled

## Database credentials

Create the database Secret before the first sync. The helper generates a
random password without printing it and applies the Secret directly to the
cluster:

```sh
./bootstrap/create-coder-postgres-secret.sh
```

To rotate the password, update the Secret with a new generated value:

```sh
./bootstrap/create-coder-postgres-secret.sh --rotate
```

CloudNativePG declarative role management applies the replacement password to
PostgreSQL. Argo CD keeps Coder configured to use the connection URI from that
same Secret.

## Verify the control plane

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"

kubectl --namespace argocd get application coder
kubectl --namespace coder-system get cluster.postgresql.cnpg.io coder-postgres
kubectl --namespace coder-system rollout status deployment/coder
kubectl --namespace coder-system get pod,service,pvc
```

The application Secret can be checked without printing its values:

```sh
kubectl --namespace coder-system get secret coder-postgres-credentials \
  --output=custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp'
```

## Access

Open the SSO-protected browser endpoint:

- <https://tiborsuty-coder.eu1.netbird.services>

The HTTPS proxy is an alternate browser entry point. Coder's canonical URL is
the private NetBird hostname below so CLI authentication cookies and callbacks
stay on one origin.

When connected to NetBird, use the private service address for the Coder CLI:

```sh
coder login http://coder.coder-system.homelab.internal
```

Workspace agents use the in-cluster address
`http://coder.coder-system.svc.cluster.local`. The custom workspace template
sets this internal agent URL so agent traffic does not pass through the browser
SSO layer.

For break-glass localhost access, forward the private Service to the Mac:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl --namespace coder-system port-forward service/coder 3000:80
```

Open `http://localhost:3000`. Port forwarding is not required during normal
operation.

## Publish the workspace template

The Terraform source is stored alongside the GitOps configuration, while Coder
stores published template versions in PostgreSQL. Publish a new version after
changing the template source:

```sh
coder templates push kubernetes-devcontainer \
  --directory infrastructure/coder/templates/kubernetes-devcontainer \
  --message "Update Kubernetes devcontainer workspace" \
  --yes
```

Create one workspace per repository. Use the SSH clone URL for a private
repository:

```sh
coder create backend-dev \
  --template kubernetes-devcontainer \
  --parameter repo=git@github.com:OWNER/backend-monorepo.git \
  --parameter service_port=3000

coder create frontend-dev \
  --template kubernetes-devcontainer \
  --parameter repo=git@github.com:OWNER/frontend-monorepo.git \
  --parameter dockerfile_path=Dockerfile.dev \
  --parameter workspace_folder=/workspace \
  --parameter service_port=5173
```

Connect from the Mac and start the terminal editor inside the workspace:

```sh
coder ssh backend-dev
cd /workspaces/project
tmux new -As dev
nvim .
```

Services use the stable DNS pattern
`coder-<owner>-<workspace>.coder-workspaces.svc.cluster.local`. Processes must
bind to `0.0.0.0` to accept connections from the other workspace.

Compose-based devcontainers are supported through their underlying development
Dockerfile. Set `dockerfile_path` and the image's expected `workspace_folder`
when creating that workspace.
