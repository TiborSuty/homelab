#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
kubeconfig=${KUBECONFIG:-"$repo_root/.local/kubeconfig"}
action=${1:-status}
if (($#)); then shift; fi

case "$action" in
  up)
    # Run from the Mac. Complete the printed company sign-in in its browser.
    exec kubectl --kubeconfig "$kubeconfig" -n nix-workspaces exec -it \
      deployment/frontend-dev -c work-vpn -- netbird up \
      --management-url https://vpn.eag-group.cloud:33073 \
      --hostname nix-fullstack-eag --no-browser "$@"
    ;;
  status|down|networks)
    exec kubectl --kubeconfig "$kubeconfig" -n nix-workspaces exec \
      deployment/frontend-dev -c work-vpn -- netbird "$action" "$@"
    ;;
  *)
    printf 'Usage: %s [up|status|down|networks] [netbird options]\n' "$0" >&2
    exit 2
    ;;
esac
