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
- Workspace permissions: disabled until the workspace template is added
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

When connected to NetBird, use the private service address for the Coder CLI:

```sh
coder login http://coder.coder-system.homelab.internal
```

Workspace agents use the in-cluster address
`http://coder.coder-system.svc.cluster.local`. The custom workspace template
must set this internal agent URL so agent traffic does not pass through the
browser SSO layer.

For break-glass localhost access, forward the private Service to the Mac:

```sh
export KUBECONFIG="$PWD/.local/kubeconfig"
kubectl --namespace coder-system port-forward service/coder 3000:80
```

Open `http://localhost:3000`. Port forwarding is not required during normal
operation.

## Next phase

Workspace Pods will run in a separate namespace. Enabling workspace RBAC and
installing the custom Kubernetes devcontainer template are intentionally not
part of this control-plane deployment.
