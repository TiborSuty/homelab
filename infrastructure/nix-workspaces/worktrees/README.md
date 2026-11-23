# Fullstack worktrees

The Mac command fullstack-worktree creates a frontend/backend worktree pair
on the existing fullstack home volume. Each pair gets its own frontend processes,
backend PHP applications, dependencies, API port and local databases. Docker
services (PostgreSQL, Redis, OpenSearch, Kafka and PHP Unit containers) remain
shared; PHP requests execute the selected worktree's code.

Backend creation uses the repository's `teas-mono worktree create` command.
Preparation uses `ai-mono composer install --no-scripts` and, from the backend
worktree directory, `teas-mono fullstack on`. This restores separate
`wt_<name>_dms_e2e`, `wt_<name>_car_audit_e2e` and `wt_<name>_admin` databases
from the existing local dump store, migrates them and checks the login flow.
It does not download remote dumps or force a restore of existing data.
The native fullstack command also ensures common services are running and
flushes the shared Redis cache; preparation can therefore invalidate cached
values in other checkouts. It does not replace their databases or source code.

From the Mac:

    fullstack-worktree create feature-a
    fullstack-worktree list
    fullstack-worktree logs feature-a --app dms
    fullstack-worktree stop feature-a
    fullstack-worktree start feature-a

Creation branches from each repository's current committed HEAD, using
worktree/feature-a as the new branch name in each repository. Uncommitted
changes in the original checkouts are preserved and are not copied.
Use --frontend-ref REF and --backend-ref REF to select different starting
commits or branches. The resulting checkouts live at:

    ~/worktrees/feature-a/frontend
    ~/worktrees/feature-a/backend  # symlink to the native backend worktree
    ~/projects/backend-monorepo/.worktrees/feature-a

Use the real backend path when running `ai-mono` or `teas-mono`, with the main
checkout's `bin` directory on PATH and `IN_DOCKER=0` in the Kubernetes workspace.
These tools scope operations by the working directory. The launcher sets that
context automatically. Backend names also obey the native tool's database-prefix
overlap restriction: `feature` and `feature-a` cannot coexist.

Dependencies are installed with the frozen lockfile using the existing pnpm
store in offline mode. If a package is unavailable locally, creation leaves
the worktree stopped. Retry with:

    fullstack-worktree prepare feature-a --online
    fullstack-worktree start feature-a

This uses the repository's normal package authentication. Install hooks do
not change the shared repository's Husky configuration. Backend dependencies
are independent copies, reconciled to each branch's Composer lockfile. Backend
installation failures keep the worktree stopped. `--online` applies to pnpm;
Composer uses its normal authentication and may fetch changed dependencies.
Re-run `prepare` while stopped after changing branches or adding migrations.
The existing local backend stack and complete local dump store must be available.

The existing DMS/IAM environment files are copied within the workspace,
with mode 0600. The worktree's local URL overrides are configured for its ports.
No environment-file contents are sent to the Mac or committed to Git.

| Slot | Workspace DMS / IAM / API | Mac DMS / IAM / API |
| --- | --- | --- |
| 1 | 4210 / 4211 / 4212 | 5300 / 5301 / 5302 |
| 2 | 4220 / 4221 / 4222 | 5400 / 5401 / 5402 |

Open the printed `http://e2e.localhost:PORT/?x-worktree=NAME` URL. Each API
listener fixes the `X-Worktree` header to its own name before forwarding to
the local gateway, including IAM and file requests. It cannot silently fall
back to main when a browser setting is missing or stale. The backend's native
HTTP client propagates this identity between services. Notifications use the
same API tunnel with a worktree-scoped `/_notifications/wt/NAME/graphql` URL.
The original checkout keeps its API at http://localhost:5800/.
Slots are retained when a worktree is stopped;
slot 6 is reserved to avoid port 5800. The create --slot N option selects an
explicit slot; otherwise the launcher selects an unused slot with available
Mac ports. Workspace port conflicts are rejected without stopping their owners.

The Kubernetes worktree-runner container supervises enabled DMS/IAM processes and API proxies.
It reloads ~/.config/nix-workspace/worktrees.json, restarts failed processes,
and resumes enabled worktrees after Pod replacement. Two worktrees may run
simultaneously within its shared limit of 32 CPUs and 28 GiB RAM. Kubernetes
requests 4 CPUs and the full 28 GiB memory budget for scheduling. The RAM cap
leaves about 2 GiB beyond the other workloads' observed peak usage on the
current ~63-GiB node; reassess it when those workloads change. Each process uses a separate
temporary Nx database. Logs are under ~/.local/state/fullstack-worktrees/.
Stopping a worktree closes its frontends, API proxy and Mac tunnels. It preserves
branches, files, dependencies, databases and port slot. Native Unit applications
remain registered and start PHP workers on demand; direct requests through the
original gateway with an explicit `X-Worktree` header can still reach them.
Backend services re-register native worktree applications on container startup.
Worktree dependency directories also keep Rspack caches separate. The two
existing DMS servers sharing the main checkout use separate ephemeral cache
mounts, preventing different server configurations from reusing the same cache.

The Nix module ~/dotfiles/nix/home/fullstack-worktrees.nix installs the Mac
CLI and the org.nix-community.home.fullstack-worktree-tunnels LaunchAgent.
The agent reads enabled worktrees over SSH every ten seconds, maintains
loopback-only forwards, and reconnects after outages. The original
fullstack-tunnel agent continues serving the main checkout and shared API.

Validate the supervisor with:

    node --test *.test.cjs

The tests use disposable Git repositories, native-tool fixtures and HTTP/WebSocket processes; it does not
touch project checkouts or production worktree configuration.
