# Nix development workspaces on Kubernetes

This is the parallel replacement for Coder's frontend and backend workspaces.
Argo CD manages the Pods, Longhorn holds project files and home directories,
and NetBird provides private SSH and HTTP access. Nix pins the development
tools. No Docker daemon, host mount, privileged container, or Kubernetes API
token is available inside a workspace.

The `nix-workspaces` Argo Application is registered in
`bootstrap/apps/kustomization.yaml` with automatic reconciliation and no
automatic pruning. Its AMD64 image is published in the private registry and
pinned by the verified registry manifest digest. Existing Coder resources and
volumes remain independent and available for rollback.

| Workspace | Persistent storage | Tools | Application port |
| --- | --- | --- | --- |
| `frontend-dev` | 50 GiB | Node 24.13.0, pnpm 12.3.4, native build tools | 4300 |
| `backend-dev` | 30 GiB | PHP 8.4, Composer, declared PHP extensions | 8080 |

The image also includes Git, Neovim, tmux, rsync and Nix. Both workspaces use
UID/GID 1000 and `/workspace/home` as their home directory. Put repositories
under `~/projects`. Nix shells are available with:

```sh
nix develop /opt/workspace-flake#frontend
nix develop /opt/workspace-flake#frontend-pnpm11
nix develop /opt/workspace-flake#backend
```

The corresponding project tools are also on PATH in ordinary SSH sessions.
The deployed `frontend` profile supplies pnpm 12.3.4, matching the selected
fresh clone of `master`. The optional `frontend-pnpm11` profile supports older
checkouts pinned to 11.22.0. Both use Node 24.13.0. Select the profile matching
the repository; do not upgrade its lockfile as part of a move. This environment
does not yet include Playwright's browser runtime,
personal dotfiles, Codex, or the Vaultwarden CLI integration.

The backend provides an editing and PHP CLI environment. Its team's NGINX
Unit image, PostgreSQL, Redis, SQS, gateway, and other Compose services have
not been migrated. A Service on port 8080 does not start a backend web server.
Validate Composer platform requirements against the chosen branch before
using this as a replacement for the team's image.

## Local verification

```sh
docker build -t homelab-nix-workspace:validation infrastructure/nix-workspaces/image
./infrastructure/nix-workspaces/image/smoke-test.sh
kubectl kustomize infrastructure/nix-workspaces
terraform -chdir=infrastructure/netbird/cloud validate
```

The live Talos nodes are AMD64. On the ARM Mac, build their image with
`docker build --platform linux/amd64 --build-arg NIX_BUILD_FILTER_SYSCALLS=false`.
The build-only flag works around emulation's lack of seccomp BPF support;
the resulting workspace retains Nix's default syscall filtering and the Pod's
`RuntimeDefault` seccomp profile. Native builds use the default `true` value.

Validation on 2026-11-04:

- ARM64 SSH, UID 1000, root-login rejection, frontend pnpm 12, backend PHP,
  Nix shells, and persistence tests passed.
- The AMD64 image built successfully. Its pnpm 11.22.0, pnpm 12.3.4 and PHP
  extension checks passed. Native AMD64 SSH and UID 1000 were verified on both
  cluster workspaces, frontend root SSH was rejected, and the frontend offline
  Nix shell passed. Source checkouts and SSH host keys survived Pod replacement.
- Kubernetes schema checks passed for nine standard resources. Two custom
  resources had no local schema. A server dry-run of the workload manifests
  in the existing baseline-policy `coder-workspaces` namespace was accepted;
  this did not create resources.
- NetBird Terraform validation passed. The applied plan added three resources,
  changed none and destroyed none. Both NetworkResources report Ready. After
  the Mac signed in, private DNS and SSH to both workspace hostnames passed;
  both SSH sessions ran as UID 1000 with host keys verified against the cluster.
- Both PVCs are healthy with two replicas. The approved Longhorn reservation
  limit is 200%; frontend remains 50 GiB and backend remains 30 GiB.
- The fresh frontend installed with pnpm 12.3.4 and `--frozen-lockfile`; its
  application container starts DMS automatically using the persisted marker.
  DMS compiled successfully with no type errors. The HTML page (`OMNETIC`)
  and `main.js` returned HTTP 200 through port-forwarding with the private
  tenant Host header. The DMS tenant URL also returned HTTP 200 directly over
  NetBird. Browser sign-in and upstream API access remain unverified.
- The restored backend is at `33c96f6e7a19a66beb5fb7e79d3723d2539dae2a`.
  `composer check-platform-reqs --lock` inside the offline backend Nix shell
  passed every runtime and development requirement, including XSL and rdkafka.
  Its tracked files are unchanged; `.coder-tools`
  remains present as copied workspace state. Composer dependencies have not
  been installed, and the backend service stack remains separate.

The user selected a fresh frontend clone. Initial source: `master` at
`531053d326485e029ed868bc94eec4bef1340f0b`. Neither Coder frontend checkout's
local edits are imported. The backend workspace has a full private backup at
`.local/nix-workspace-migration/backend-workspace.tar.gz` with a SHA-256 record
alongside it; its original Coder volume remains intact.

The smoke test uses a disposable Docker volume and temporary SSH key. It
checks real SSH authentication, UID 1000, rejection of root SSH, exact frontend
versions, required PHP extensions, `nix develop`, and file/host-key persistence
after container replacement. It publishes SSH only on localhost and cleans up
its own container, volume, and key.

The SSH supervisor starts as container root so OpenSSH can perform privilege
separation and switch to UID 1000. Password authentication and root SSH are
disabled. Kubernetes applies the baseline Pod Security policy with explicitly
listed capabilities. This is a single-user workspace: its Nix store is writable
by that user, and Nix build sandboxing is disabled inside the container.

At startup the public-key Secret is copied to a root-owned file under `/etc/ssh`
so OpenSSH's strict permission checks accept it. Restart the workspace Pods
after changing authorized keys. Private keys are never copied to the cluster.

Home and SSH host keys persist on the PVC. The Nix store is part of the image
and writable container layer, so extra packages installed interactively must
be fetched again after Pod replacement. Add frequently used tools to the
flake and rebuild the image. PVC pruning is disabled and the StorageClass
uses `Retain`; neither setting replaces an off-cluster backup.

## Deployment order

1. Check cluster and private-registry connectivity. Check node, Longhorn and
   registry health before allocating the two new volumes.
2. Build for the cluster's verified architecture, run the smoke test, and push
   the image to `registry.homelab.internal/dev/nix-workspace`. Use the existing
   registry administrator's credentials through a temporary Docker config;
   do not put credentials in command arguments or Git. Set the Deployment
   image in `base/workspace.yaml` to the published `@sha256:...` digest.
3. Sync the registry configuration containing the new `dev/**` read policy.
   Run `bootstrap/create-registry-secrets.sh` to add the
   `nix-workspaces-pull` identity without rotating existing passwords. Then run:

   ```sh
   ./bootstrap/create-nix-workspace-ssh-secret.sh ~/.ssh/id_ed25519.pub
   ./bootstrap/create-nix-workspace-registry-secret.sh
   ```

   These helpers accept `KUBECONFIG`. The pull identity can only read `dev/**`.
   Private SSH keys stay on the client; the cluster receives only public keys.
4. Plan and apply the NetBird Terraform change. It creates a dedicated group
   and permits approved `dashboard-clients` to access ports 2222 and 80 only
   for that group. It also creates the DMS tenant wildcard record.
5. Commit/publish the reviewed GitOps changes, add `nix-workspaces.yaml` to
   `bootstrap/apps/kustomization.yaml`, then sync the new Argo Application.
   Automatic reconciliation keeps the declared workspace resources in sync.
6. Verify image pulls, PVC attachment, both Deployments, NetBird resource
   reconciliation, SSH access, and HTTP access before importing any data.

Expected private endpoints after reconciliation:

```sh
ssh -p 2222 dev@frontend-dev.nix-workspaces.homelab.internal
ssh -p 2222 dev@backend-dev.nix-workspaces.homelab.internal
```

DMS tenant URL: `http://app.frontend-dev.nix-workspaces.homelab.internal`.
The Service preserves the Host header and forwards to port 4300. The dev
server must accept this hostname and bind to `0.0.0.0`. HTTP access relies on
the NetBird policy; there is no Coder owner-authenticated application proxy.

For an initial connectivity check with Kubernetes access:

```sh
kubectl -n nix-workspaces port-forward service/frontend-dev 2222:2222
ssh -p 2222 dev@127.0.0.1
```

Use the actual host key fingerprint from a trusted `kubectl exec` session
when accepting the initial SSH connection. SSH host keys live under
`/workspace/ssh` and survive Pod replacement.

## Migrate each existing workspace

Inventory each Coder workspace's branch, uncommitted/untracked files, ignored
environment files, personal configuration, and persistent CLI state first.
Take an independent backup. Copy into a new directory under `~/projects` on
the matching Nix workspace; do not rebind, move, or delete the original PVC.
Compare file inventories and Git status after copying. Reinstall generated
dependencies with the pinned tools instead of copying platform-specific
`node_modules` between architectures.

Private repository authentication and app environment files must be provisioned
at runtime. Keep the existing command-scoped secret workflow; never place
tokens, `.env` contents, or private keys in a Nix expression or image layer.
Agent forwarding is disabled. The SSH login key is not a Git server credential.

The frontend `application` container waits for
`/workspace/home/.frontend-ready`. After a fresh clone and dependency install,
create that marker as `dev` to start DMS. Its startup script copies the
namespace-local `frontend-dms-environment` Secret to `apps/dms/.env` with mode
600, then starts Nx on port 4300. Kubernetes restarts the application process
and starts it again after Pod replacement. The app has a 16 GiB memory limit
for compilation, two type-check workers, and HTTP readiness checks. Its Nx
process database is temporary so stale PIDs cannot block startup after a restart.
From the frontend checkout:

```sh
SKIP_CARAUDIT_POSTINSTALL=true pnpm install --frozen-lockfile
touch ~/.frontend-ready
```

Verify tenant routing, authentication redirects and API access. Follow startup
with `kubectl -n nix-workspaces logs deployment/frontend-dev -c application`.
For the backend, verify `composer check-platform-reqs` and the required CLI
commands after restoring its dependency/authentication setup.

Only retire Coder after both workspaces pass those checks and personal tooling
has been migrated. Removing Coder also requires reviewing its Argo Application,
PostgreSQL database, Terraform-managed resources and NetBird routes separately.
