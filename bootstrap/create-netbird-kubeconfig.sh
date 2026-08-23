#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubeconfig_path="${NETBIRD_KUBECONFIG:-${repo_root}/.local/netbird-kubeconfig}"

mkdir -p "$(dirname "${kubeconfig_path}")"

KUBECONFIG="${kubeconfig_path}" kubectl config set-cluster homelab \
  --server=https://homelab.netbird-kubeapi-proxy.netbird.cloud \
  --insecure-skip-tls-verify=true >/dev/null

KUBECONFIG="${kubeconfig_path}" kubectl config set-credentials netbird \
  --token=none >/dev/null

KUBECONFIG="${kubeconfig_path}" kubectl config set-context homelab \
  --cluster=homelab \
  --user=netbird \
  --namespace=default >/dev/null

KUBECONFIG="${kubeconfig_path}" kubectl config use-context homelab >/dev/null
chmod 600 "${kubeconfig_path}"

printf 'NetBird kubeconfig written to %s\n' "${kubeconfig_path}"
