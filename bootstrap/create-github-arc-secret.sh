#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
namespace=arc-runners
secret_name=github-arc-auth

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

if kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" >/dev/null 2>&1 && \
  [ "${GITHUB_ARC_ROTATE:-0}" != "1" ]; then
  echo "Secret $namespace/$secret_name already exists."
  echo "Set GITHUB_ARC_ROTATE=1 to replace it."
  exit 0
fi

github_arc_token=${GITHUB_ARC_TOKEN:-}

if [ -z "$github_arc_token" ]; then
  if [ ! -t 0 ]; then
    echo "Set GITHUB_ARC_TOKEN or run this helper from an interactive terminal." >&2
    exit 1
  fi

  printf 'GitHub fine-grained token for ARC: ' >&2
  terminal_settings=$(stty -g)
  trap 'stty "$terminal_settings"' HUP INT TERM
  stty -echo
  IFS= read -r github_arc_token
  stty "$terminal_settings"
  trap - HUP INT TERM
  printf '\n' >&2
fi

: "${github_arc_token:?GitHub token is empty}"

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" \
  >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig_path" create namespace "$namespace"

kubectl --kubeconfig "$kubeconfig_path" label namespace "$namespace" \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite >/dev/null

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret generic "$secret_name" \
  --from-literal=github_token="$github_arc_token" \
  --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

unset github_arc_token

echo "Created Secret $namespace/$secret_name."
echo "No GitHub credential was written to the repository."
