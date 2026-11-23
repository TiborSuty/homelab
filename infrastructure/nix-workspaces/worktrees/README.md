# Fullstack worktrees

The Mac command fullstack-worktree creates a frontend/backend worktree pair
on the existing fullstack home volume. It gives the frontend its own dependency
installation, DMS/IAM ports, browser URLs, and hot reload connections.
The backend API and database remain shared with the original backend checkout.
Editing a backend worktree does not change the backend currently running.

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
    ~/worktrees/feature-a/backend

Dependencies are installed with the frozen lockfile using the existing pnpm
store in offline mode. If a package is unavailable locally, creation leaves
the worktree stopped. Retry with:

    fullstack-worktree prepare feature-a --online
    fullstack-worktree start feature-a

This uses the repository's normal package authentication. Install hooks do
not change the shared repository's Husky configuration. Backend dependencies
and migrations are not run by this launcher.

The existing DMS/IAM environment files are copied within the workspace,
with mode 0600. The worktree's local URL overrides are configured for its ports.
No environment-file contents are sent to the Mac or committed to Git.

| Slot | Workspace DMS / IAM | Mac DMS / IAM |
| --- | --- | --- |
| 1 | 4210 / 4211 | 5300 / 5301 |
| 2 | 4220 / 4221 | 5400 / 5401 |

Open the printed http://app.localhost:PORT/ URL. The shared API remains
http://localhost:5800/. Slots are retained when a worktree is stopped;
slot 6 is reserved to avoid port 5800. The create --slot N option selects an
explicit slot; otherwise the launcher selects an unused slot with available
Mac ports. Workspace port conflicts are rejected without stopping their owners.

The Kubernetes worktree-runner container supervises enabled DMS/IAM processes.
It reloads ~/.config/nix-workspace/worktrees.json, restarts failed processes,
and resumes enabled worktrees after Pod replacement. Two worktrees may run
simultaneously within its 32 GiB memory limit. Each process uses a separate
temporary Nx database. Logs are under ~/.local/state/fullstack-worktrees/.
Stopping a worktree preserves its branches, files, dependencies and port slot.

The Nix module ~/dotfiles/nix/home/fullstack-worktrees.nix installs the Mac
CLI and the org.nix-community.home.fullstack-worktree-tunnels LaunchAgent.
The agent reads enabled worktrees over SSH every ten seconds, maintains
loopback-only forwards, and reconnects after outages. The original
fullstack-tunnel agent continues serving the main checkout and shared API.

Validate the supervisor with:

    node --test worktrees.test.cjs

The test uses disposable Git repositories and HTTP processes; it does not
touch project checkouts or production worktree configuration.
