#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
namespace=netbird
secret_name=netbird-mgmt-api-key

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
  [ "${NETBIRD_ROTATE:-0}" != "1" ]; then
  echo "Secret $namespace/$secret_name already exists."
  echo "Set NETBIRD_ROTATE=1 to replace it."
  exit 0
fi

netbird_api_token=${NETBIRD_API_TOKEN:-}

if [ -z "$netbird_api_token" ]; then
  if [ ! -t 0 ]; then
    echo "Set NETBIRD_API_TOKEN or run this helper interactively." >&2
    exit 1
  fi

  printf 'NetBird personal access token: ' >&2
  terminal_settings=$(stty -g)
  trap 'stty "$terminal_settings"' HUP INT TERM
  stty -echo
  IFS= read -r netbird_api_token
  stty "$terminal_settings"
  trap - HUP INT TERM
  printf '\n' >&2
fi

: "${netbird_api_token:?NetBird token is empty}"

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" \
  >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig_path" create namespace "$namespace"

# NetworkRouter Pods require elevated networking capabilities. The operator and
# ClusterProxy containers still use their own restrictive security contexts.
kubectl --kubeconfig "$kubeconfig_path" label namespace "$namespace" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite >/dev/null

# Feed the token through stdin so it is neither written to disk nor included in
# the kubectl process arguments.
printf '%s' "$netbird_api_token" | \
  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
    create secret generic "$secret_name" \
    --from-file=NB_API_KEY=/dev/stdin \
    --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

unset netbird_api_token

echo "Created Secret $namespace/$secret_name."
echo "No NetBird credential was written to the repository."
