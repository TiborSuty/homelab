# Nix development workspaces on Kubernetes

These are the frontend and backend development workspaces, replacing Coder.
Argo CD manages the Pods, Longhorn holds project files and home directories,
and NetBird provides private SSH and HTTP access. Nix pins the development
tools. No Docker daemon, host mount, privileged container, or Kubernetes API
token is available inside a workspace.

The `nix-workspaces` Argo Application is registered in
`bootstrap/apps/kustomization.yaml` with automatic reconciliation and no
automatic pruning. Its AMD64 image is published in the private registry and
pinned by the verified registry manifest digest.

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
Codex or the Vaultwarden CLI integration. The frontend workspace uses the
shared Home Manager configuration described below; the separate backend
workspace retains its previous image.

The backend provides an editing and PHP CLI environment. Its team's NGINX
Unit image, PostgreSQL, Redis, SQS, gateway, and other Compose services have
not been migrated. A Service on port 8080 does not start a backend web server.
Validate Composer platform requirements against the chosen branch before
using this as a replacement for the team's image.

## Shared Mac and workspace tools

The image flake imports `nix/home/workspace.nix` from
[`TiborSuty/dotfiles`](https://github.com/TiborSuty/dotfiles/tree/shared-development-tools/nix/home).
Its `common.nix` is also imported by the Mac's Home Manager configuration.
This is the single declaration for Neovim, Git, lazygit, tmux, ripgrep, fd,
fzf, Tree-sitter, and global Nx. Nx 23.2.1 is pinned in
`nix/packages/nx`, including its npm runtime dependencies and native bindings.
It uses a Nix-managed Node interpreter without replacing the project Node
toolchain, and delegates to a repository-local Nx installation when present.
It also imports `shell.nix`, sharing Zsh history,
completion, autosuggestions, syntax highlighting, Oh My Zsh snippets, fzf-tab,
fzf, zoxide, and the Starship theme. Portable initialization lives in
`shell-init.zsh`. Homebrew, OrbStack, Mac project paths, NVM, and command-scoped
secret helpers stay in the Mac module, along with Git identity and app settings.
The workspace's project Node/PHP profiles remain separate.
Each platform retains its existing Nixpkgs pin, so versions can differ.

The workspace lockfile pins both the shared dotfiles revision and Home
Manager. The Docker build builds the Home Manager generation at
`/opt/home-manager` and fetches that exact dotfiles commit into `/opt/dotfiles`.
At startup, as UID 1000, it clones the bundled repository into `~/dotfiles`
only if that path does not exist, then activates Home Manager. No startup
network fetch is required. The persistent `.bashrc` and `.bash_profile` are
not managed or replaced.

The workspace image uses `/opt/tools/bin/zsh` as the SSH login shell.
Home Manager manages `.zshenv`/`.zshrc` and the Starship configuration;
Zsh sources an existing `~/.config/nix-workspace/fullstack.sh` to retain both
Node and PHP toolchains in interactive sessions and non-interactive SSH
commands. The image's profile-selected toolchain remains available for an
empty home. Bash is retained for scripts and `bash -l` fallback. An existing
unmanaged Zsh configuration causes activation to stop rather than overwrite it.

Neovim's `~/.config/nvim` points to the writable
`~/dotfiles/.config/nvim` directory, using the same Lua configuration and
`lazy-lock.json` as the Mac's repository. Plugin installation still requires
network access on first use; run `:Lazy restore` to restore pinned plugins.
Tree-sitter is also supplied by Nix so LazyVim does not download a Linux
binary that expects a system loader absent from the workspace image.
tmux is shared as a package; its Mac-specific configuration and plugin
submodules are not activated in the workspace.

Startup never resets or pulls an existing dotfiles checkout. Editor edits and
plugin lockfile changes survive container replacement. To synchronize an
existing checkout, review `git -C ~/dotfiles status`, commit or preserve local
changes, then use Git to fetch and merge the intended dotfiles revision.
Changes are shared through Git, not live filesystem synchronization.

For an existing unmanaged `~/.config/nvim`, Home Manager stops with a conflict
instead of overwriting it. Compare and back up that configuration before
moving it aside and restarting. Existing `~/dotfiles` must contain
`.config/nvim/init.lua`; startup preserves an unexpected directory and fails
with a diagnostic.

To update the image after publishing shared dotfiles changes:

```sh
cd infrastructure/nix-workspaces/image
nix flake update dotfiles
cd ../../..
docker build -t homelab-nix-workspace:shared-home-manager infrastructure/nix-workspaces/image
./infrastructure/nix-workspaces/image/smoke-test.sh homelab-nix-workspace:shared-home-manager
```

Review the lockfile, build/test the cluster's AMD64 image, publish it, and
update only the intended workspace-container digest through GitOps. Keep the
DMS application-container digest unchanged. A new image updates installed
tools and Home Manager links; existing writable dotfiles are synchronized
separately as described above.

Validated on 2026-11-04: the ARM64 smoke test passed offline activation,
unmanaged-config protection, writable Neovim configuration, shared tools over
SSH, frontend/backend offline Nix shells, and persistence across replacement
with a different Home Manager generation.

Deployed to `frontend-dev` on 2026-11-05 with shared dotfiles revision
`5b6ff6c154c890b6164429837f40df8c3d4f6a95` and image digest
`sha256:f325402ba39092ff5ae54fc452f9dde9a5abffc80db01a32991fff59bcd4bcc9`.
A disposable native AMD64 pod passed SSH, root-login rejection, offline
Node/PHP shells, repeat activation preserving editor/shell changes, LazyVim
startup, and Tree-sitter parser compilation/loading. Tree-sitter comes from
Nix because the Mason-downloaded Linux executable expected an absent loader.
The registry uploader used command-scoped `GODEBUG=http2client=0` to avoid
stalled HTTP/2 blob checks, retaining TLS certificate verification.

The live workspace activated Home Manager successfully. Both repository
commits and worktree state, persistent shell files, the multi-root workspace
file, and SSH host key survived replacement unchanged. The frontend Pod
became ready and its HTML and JavaScript endpoints returned HTTP 200; its
unchanged application container recovered from one Nx plugin-worker timeout
on startup. Argo reports Synced/Healthy and Longhorn volumes are healthy.
The separate backend workspace and DMS application retain their existing
image digests. Mac activation was pending at this initial deployment; the later Zsh and Nx
activations are recorded below.

The shared Zsh rollout on 2026-11-05 uses image digest
`sha256:a03c1e5f55d668493753efc87b0a9593bb1e35d350c3ace235079460edc20c8b`
and pins dotfiles revision
`85b81e28ab77e35d686f2ebd141758125d97beeb`. Native AMD64 validation started
with the previously deployed image's Home Manager generation and an edited
persistent home. Migration and repeat activation preserved the Bash files,
project PATH setup, and Neovim edits. Interactive SSH verified Zsh 5.9.1,
Starship, zoxide, completion, suggestions, highlighting, aliases, and history;
non-interactive SSH retained both project toolchains, and offline Nix shells
passed. Live SSH confirmed the same shell integrations and both project
toolchains. The existing workspace dotfiles checkout was explicitly
fast-forwarded to the pinned commit; its modified Neovim lockfile, existing
Bash files, both project repositories (including local frontend edits), and
SSH host key were preserved. Startup still never automatically pulls or
resets that checkout. The Mac nix-darwin build and generated interactive Zsh
startup passed. The user then activated the matching Mac generation; live
Zsh checks confirmed the shared prompt, plugins, aliases, and history settings.
The live frontend became ready and returned HTTP 200 for HTML and JavaScript
through a Kubernetes port-forward; its bundle rebuilt because existing project
package/lockfile edits invalidated the cache. The Mac's NetBird session was
expired during initial verification. After the user reauthenticated, NetBird
reported Connected and direct `ssh fullstack` succeeded with Zsh 5.9.1 and
both Node/PHP toolchains. Argo reported Synced/Healthy after the rollout.


Global Nx was deployed on 2026-11-05 with dotfiles revision
`5ee4ab8e66408f4660b36f262e16be94f64aa22c` and workspace image
`sha256:fdf618757be88ad184350354dd511964bf7ca1d58dc8689dd5456e4b64364b06`.
Nx 23.2.1 passed native binding loading and task execution on both Apple
Silicon macOS and a disposable native AMD64 pod. The Mac generation was
activated and its old npm-global Nx removed after backup, so `nx` resolves
to Home Manager. Direct `ssh fullstack` verified global Nx and delegation to
the frontend repository's local Nx 23.2.1; Node/PHP toolchains were retained.
The workspace dotfiles checkout was fast-forwarded explicitly. Existing
project edits, Neovim lockfile, shell files, and SSH host key were preserved.
The application recovered from one plugin-worker startup timeout and returned
HTTP 200 for HTML and JavaScript. Argo reported Synced/Healthy. Only the
frontend workspace image changed; the application and backend workspace
images and persistent volume claims stayed unchanged.


Fullstack Docker uses the Nixpkgs-pinned `docker-client` package, which includes
`docker compose` and `docker buildx`. The frontend deployment adds a Docker
29 engine pinned by digest in `frontend/docker-engine.yaml`. It listens only
on `/var/run/docker.sock`, shared with the workspace and accessible to the
`dev` user's GID 1000. No Docker TCP API or node runtime socket is exposed.
The engine mounts the existing home volume at the same `/workspace` path,
so Compose bind mounts from the project checkout resolve correctly. Use
paths under `/workspace` for bind mounts; the client's `/tmp` is not shared.

Docker images, named volumes, and container state use the separate 50 GiB
`frontend-docker-data` Longhorn PVC, retained on GitOps pruning/deletion.
The engine has a 16 GiB memory limit; the SSH workspace retains its 32 GiB
limit. Published Docker ports share the Pod's network namespace with SSH and
the frontend application, so avoid occupied ports such as 2222 and 4300.
Forward a backend port through SSH when accessing it from the Mac.

Docker-in-Docker needs a privileged engine container. The user explicitly
approved changing the `nix-workspaces` namespace enforcement from `baseline`
to `privileged`; restricted audit and warning labels remain. The existing
workspace, application, and backend container security contexts are unchanged.
This namespace policy allows privileged workloads and weakens isolation from
the node; it is an intentional exception for this development environment.

Verify Docker over `ssh fullstack` with `docker version`, `docker compose
version`, and `docker info`. The optional `image/check-docker.sh` integration
check runs as UID 1000 against a running engine, creates a disposable Compose
project under `/workspace`, and checks Buildx, source bind mounts, published
ports, service DNS, and named-volume persistence before cleaning up.
Installing Docker does not automatically start the backend stack or initialize
its databases; use the backend repository's documented development commands.


Docker was deployed and verified on 2026-11-05 using workspace image
`sha256:74bcc1d9fe3394e2ff337801bc85ba99c413a61b0cc97214a04b73bf5ad80842`.
Direct SSH reported client 29.9.2, engine 29.9.3, and Compose 5.4.0. The live
integration check passed image builds, source mounts, published ports, service
DNS, and named-volume persistence across container recreation. Existing project
worktrees, shell/editor files, and the SSH host key were unchanged. Fullstack
was 3/3 Ready with zero restarts, the frontend returned HTTP 200, and Argo
reported Synced/Healthy. Disposable test workloads and credentials were removed.


Backend Compose reads `CARVAGO_GITHUB_ACCESS_TOKEN` and
`CARVAGO_GITLAB_ACCESS_TOKEN` to construct the Composer container's
`COMPOSER_AUTH`. These variables are intentionally absent from ordinary SSH
sessions. Run a non-interactive backend command from the Mac using the
existing Vaultwarden wrapper:

```sh
cd ~/Documents/github/homelab
with_dev_secrets python3 infrastructure/nix-workspaces/with-backend-secrets.py \
  bin/ai-mono project dms doctor
```

Replace the command after the Python script with the intended backend command;
it runs from `~/projects/backend-monorepo` in `fullstack`. The Mac wrapper
prompts locally for vault unlocking and locks it again when the command ends.
The transport sends only the two required tokens over encrypted SSH stdin;
it does not write token files, add SSH environment-acceptance rules, or export
values into interactive shells. It supports non-interactive commands, with
stdin closed. Compose can retain the resulting `COMPOSER_AUTH` in the Composer
container configuration, as defined by the backend repository. No real tokens
are used by `test-with-backend-secrets.py` or the transport's validation.


The workspace can also connect directly to Vaultwarden. Its Home Manager
module provides Bitwarden CLI 2026.10.1 from the same independent Nixpkgs pin
as the Mac, a `bw` wrapper with the public CA certificate, and an executable
`with_dev_secrets` available from any shell. Fresh activation configures
`https://vaultwarden.vaultwarden.svc.cluster.local`; an existing CLI state
pointing elsewhere is preserved and causes activation to stop for review.
The private CLI state lives in `~/.local/share/bitwarden-workspace` on the home
PVC. No account, vault session, password, or token is bundled into the image.

Log into the CLI once from your own terminal (enter credentials only at the
interactive prompts):

```sh
ssh fullstack
bw login --quiet && bw lock
cd ~/projects/backend-monorepo
with_dev_secrets bin/ai-mono project dms doctor
```

To give OpenCode and its child commands the tokens for a session, start it
with `with_dev_secrets opencode` from the backend checkout. An already-running
OpenCode process does not inherit tokens from a later command. The helper
prompts for vault unlocking, fetches only the two
existing GitHub/GitLab token items, passes them to the child command, and
locks the CLI vault afterwards. Phrase lookup remains disabled. Real login
and token retrieval require the user's credentials; mock tests cover cleanup,
empty values, failures, and command exit status without accessing a real vault.
The Mac-to-workspace wrapper above remains an optional alternative.

The direct integration was deployed and verified on 2026-11-05 using workspace
image `sha256:8c6f975e4b9da4615d1aeed81bf5b1b1737252a7a8e518a92a54ed960c2bd51e`
and shared dotfiles `78f8f91861bec0b01cb40c04cb2e734bf76ecc66`. Native AMD64
validation passed the mock secret-flow checks and repeat activation preserved
CLI state. The live CLI reported unauthenticated, Vaultwarden returned HTTP
200 with CA verification, and CLI state permissions were 0700/0600. Fullstack
was 3/3 Ready, Argo Synced/Healthy, and the frontend returned HTTP 200. Docker,
the 32 GiB workspace limit, volume claims, SSH host key, and existing project
changes were preserved. Actual vault login and token retrieval remain a user
step and were not tested with real credentials.

The fullstack Pod also has an independent EAG NetBird client configured for
`https://vpn.eag-group.cloud:33073`, matching the Mac's saved EAG profile.
It uses NetBird 0.82.0 pinned by image digest and a dedicated 1 GiB PVC
(`frontend-work-vpn-data`). Only public initial settings are in Git; the
client generates its own keys. Existing identity state is never overwritten.
The Mac's profile and keys are not copied or changed.

From the Mac's homelab checkout, enroll the workspace using company SSO:

```sh
./infrastructure/nix-workspaces/work-vpn.sh up
```

Open the printed sign-in URL in the Mac browser. The peer is named
`nix-fullstack-eag`; company approval or access-policy assignment may be needed.
Check or disconnect it using the same script with `status` or `down`.
`networks list` lists assigned networks. The script uses `.local/kubeconfig`
by default (or the `KUBECONFIG` environment variable).

NetBird shares the Pod network with the workspace and Docker engine. The
backend's `docker run --network host` database-download command therefore
uses this VPN network. Following the company's EAG VPN instructions, only the
management URL is seeded as an advanced setting; routing, inbound connections,
IPv6 and DNS use NetBird defaults. The container has NET_ADMIN, NET_RAW,
NET_BIND_SERVICE and SYS_RESOURCE capabilities, with no node network, node
filesystem, Kubernetes credentials or Docker socket. Kernel WireGuard was
checked on a native Talos node; no host TUN device mount is needed here.

A pinned CoreDNS sidecar sends `cluster.local` and `homelab.internal` directly
to cluster DNS (10.96.0.10). Other queries prefer NetBird's default resolver
on this enrolled peer's persistent VPN IP, 100.72.38.175:53, falling back to
cluster DNS on transport errors, SERVFAIL or REFUSED. Recheck that upstream
address if the peer is deleted/re-enrolled or renumbered. Consumers use the
Pod IP as their nameserver so nested Docker containers can reach it too.
NetBird manages only its own container's resolver file using its defaults.
DNS availability and daemon readiness do not imply company resource access.

Native canary validation on 2026-11-05 checked the daemon while logged out,
0700/0600 state permissions, kernel WireGuard, company-server TLS, Vaultwarden
HTTPS, and DNS from Docker bridge and host networking. A temporary mock VPN
DNS server verified company-query routing while Kubernetes names stayed on
cluster DNS. Actual EAG routes, internal DNS and application reachability
must be verified after the user completes company SSO. No AWS configuration
or database download is part of this VPN rollout.

The pre-login rollout was verified at commit `a887a05`: fullstack was 5/5
Ready with zero restarts, Argo Synced/Healthy, SSH reachable, and frontend
HTTP 200. Workspace/Docker DNS and Vaultwarden HTTPS passed. Existing project
files, SSH host key, image versions, resource limits and data-volume claims
were preserved; all Longhorn volumes were healthy. The VPN reported
`NeedsLogin` at that pre-login check. Enrollment subsequently succeeded, but
the server distributed zero peers, networks and DNS servers. The user then
provided the EAG VPN guide, which requires default advanced settings apart
from the management URL. The earlier client overrides were removed and a
one-time init migration clears those settings without changing enrollment
keys. Normal startup does not replace the saved identity. File logging is
also enabled so `netbird debug bundle -A` can include daemon logs, as requested
by the company guide. Do not upload a bundle automatically.

The correction was verified at `f6bbb9e`: all five advanced overrides were
cleared, the same peer IP/public key survived the restart, and NetBird
reconnected without another SSO login. Direct default NetBird DNS and the
workspace proxy both resolved cluster/public names; the documented internal
host `emailengine.i.omnetic.com` returned ENODATA. The server still supplied
zero peers, networks and nameservers. The user confirmed using the same
company Google EAG account as on the Mac. An anonymized `netbird debug bundle
-A` was saved locally for a company DevOps report; no upload was performed.
The workspace returned to 5/5 Ready and frontend HTTP 200 after one automatic
Nx plugin-worker startup retry. Existing project files were preserved.

AWS CLI v2 is part of the Nix workspace toolset (`awscli2` from the existing
locked Nixpkgs revision). It is available as `aws` in normal SSH sessions and
all workspace development shells. AWS configuration and SSO cache belong in
`~/.aws` on the persistent home volume; credentials are not built into the
image or committed to Git.

For an SSH-based workspace, configure SSO using a device code so the browser
can run on the Mac without forwarding a localhost callback:

```sh
aws configure sso --use-device-code --no-browser
```

Follow the company AWS setup for the portal, region, account and role. Installing
the CLI does not authenticate AWS or grant VPN access. The backend's fullstack
download also needs an authorized AWS profile and connectivity to its dev RDS
endpoint. See the [AWS SSO configuration reference](https://docs.aws.amazon.com/cli/latest/reference/configure/sso.html).

AWS CLI rollout verified on 2026-11-05: fullstack uses image
`sha256:cf6888e99176b8ff64b9904d139ad4ea0ebc9a1286b82d1e20187433e0d8c690`
with AWS CLI **2.34.24**. Native AMD64 validation covered normal SSH, SSO/ECR/RDS
command models, and the offline backend Nix shell. The live rollout preserved
home configuration, repository changes, SSH host key and VPN identity; all 18
previously running Docker containers were restored and DMS container DNS worked.
The frontend returned HTTP 200 and Argo reported Synced/Healthy. No AWS profile
was configured and no database download was performed; company VPN access was
still missing routes, peers and DNS assignments.

### HashiCorp Vault CLI

The workspace toolset includes `vault-bin` from the pinned Nixpkgs revision.
It provides HashiCorp's official `vault` CLI in normal SSH sessions and all
workspace Nix development shells. The package set permits only `vault-bin`
under its BSL license; it does not enable unrestricted unfree packages or run
a Vault server.

The frontend environment downloader uses this CLI. Connect the workspace EAG
VPN, authenticate interactively, then download the local environments:

```sh
# From the homelab checkout on the Mac, if the VPN session has expired:
./infrastructure/nix-workspaces/work-vpn.sh up

# Inside ssh fullstack:
vault login -address=https://vault.dev.i.omnetic.dev
cd ~/projects/frontend-monorepo
pnpm run download-environments:local
```

Enter the Vault token at the terminal prompt. Tokens and downloaded environment
values must stay out of Git and Nix store-backed configuration. CLI installation
alone does not authenticate Vault or renew the company VPN session.

Vault rollout verified on 2026-11-06: fullstack uses image
`sha256:8fe9e1de7f526ec775f087d914754d9225ab548112a80a34bb73375e59140109`
with Vault **2.0.0**. Native AMD64 tests covered the CLI, login/KV/token commands,
and the offline frontend Nix shell. Live SSH and `pnpm exec vault version`
passed. All 21 previously running Docker containers were restored, both
frontend ports (4200 and 4300) returned HTTP 200, and the automatic Mac tunnel
on 5200 reconnected successfully. Persistent configuration, repository edits,
OpenCode policy, Docker override, frontend environment and SSH host key were
preserved. Argo was Synced/Healthy and Longhorn volumes were healthy. The EAG
VPN session needed login; Vault authentication and environment download were
not performed.

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
alongside it. The retired workspace volumes are archived separately; see the
retirement record below.

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
   Seed the frontend environment Secret from a protected local file:

   ```sh
   kubectl -n nix-workspaces create secret generic frontend-dms-environment \
     --from-file=dms.env=/path/to/apps/dms/.env
   ```
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

## Project files and runtime secrets

Keep repositories under `~/projects` and back up uncommitted work, ignored
environment files, and personal CLI state. Install dependencies with the pinned
tools rather than copying platform-specific `node_modules` between architectures.

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

## Coder retirement

The user requested complete removal on 2026-11-04. The retired scope includes
Coder's Argo Application, control plane, gateway, four workspaces, PostgreSQL,
five volumes, workspace StorageClass, and Coder-specific NetBird routes, DNS,
and public reverse proxy. The shared CloudNativePG and NetBird operators remain
in use by other services.

Before deletion, manifests, Secrets, Terraform state, the original template files
(including local uncommitted changes), and stopped volume contents were saved
under `.local/coder-removal-20261104-124945/`. Archives include checksums and
file inventories. Reinstallable `node_modules` and the root `.pnpm-store` cache
are excluded. Coder's PostgreSQL was already crash-looping; its stopped files are preserved as-is, without a
successful logical database restore test. These local backups are private and
are not committed to Git.
