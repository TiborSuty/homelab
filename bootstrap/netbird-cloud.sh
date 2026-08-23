#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
terraform_directory="$repository_root/infrastructure/netbird/cloud"
namespace=netbird
secret_name=netbird-mgmt-api-key
action=${1:-plan}

if [ "$#" -gt 0 ]; then
  shift
fi

if ! command -v tofu >/dev/null 2>&1; then
  echo "OpenTofu 1.12 or newer is required. Install it with: brew install opentofu" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

case "$action" in
  fmt)
    exec tofu -chdir="$terraform_directory" fmt "$@"
    ;;
esac

if ! kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" >/dev/null 2>&1; then
  echo "Secret $namespace/$secret_name does not exist." >&2
  echo "Create it with ./bootstrap/create-netbird-api-secret.sh" >&2
  exit 1
fi

netbird_pat=$(kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" -o jsonpath='{.data.NB_API_KEY}' | base64 --decode)

: "${netbird_pat:?NetBird token is empty}"

export KUBE_CONFIG_PATH="$kubeconfig_path"
export NB_PAT="$netbird_pat"
unset netbird_pat

tofu -chdir="$terraform_directory" init -input=false >/dev/null
exec tofu -chdir="$terraform_directory" "$action" "$@"
