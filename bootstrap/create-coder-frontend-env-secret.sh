#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
namespace=coder-workspaces
secret_name=coder-frontend-dms-environment
source_workspace=frontend-dev-2
source_owner=TiborSuty
source_file=
rotate=false
environment_payload=

usage() {
  cat >&2 <<EOF
usage: $0 [--workspace NAME] [--owner USER] [--file PATH] [--rotate]

Seeds $namespace/$secret_name without printing its contents. By default the
environment is copied from /workspace/apps/dms/.env in frontend-dev-2.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      source_workspace=$2
      shift 2
      ;;
    --owner)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      source_owner=$2
      shift 2
      ;;
    --file)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      source_file=$2
      shift 2
      ;;
    --rotate)
      rotate=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

cleanup() {
  unset environment_payload
}
trap cleanup 0
trap 'exit 1' 1 2 15

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required" >&2
  exit 1
}

test -r "$kubeconfig_path" || {
  echo "kubeconfig is not readable: $kubeconfig_path" >&2
  exit 1
}

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" \
  >/dev/null 2>&1 || {
    echo "namespace $namespace does not exist" >&2
    exit 1
  }

if kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  get secret "$secret_name" >/dev/null 2>&1 && test "$rotate" = false; then
  echo "Secret $namespace/$secret_name already exists."
  echo "Use --rotate to replace it."
  exit 0
fi

if [ -n "$source_file" ]; then
  test -s "$source_file" || {
    echo "environment file is missing or empty: $source_file" >&2
    exit 1
  }

  environment_payload=$(cat "$source_file"; printf x)
  environment_payload=${environment_payload%x}
else
  source_selector="com.coder.workspace.name=$source_workspace,com.coder.user.username=$source_owner"
  source_pod=$(kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
    get pods --selector "$source_selector" --field-selector status.phase=Running \
    --output=jsonpath='{.items[0].metadata.name}')

  test -n "$source_pod" || {
    echo "no running Pod found for $source_owner/$source_workspace" >&2
    exit 1
  }

  kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
    wait --for=condition=Ready "pod/$source_pod" --timeout=10s >/dev/null
  kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
    exec "$source_pod" -- test -s /workspace/apps/dms/.env

  environment_payload=$(kubectl --kubeconfig "$kubeconfig_path" \
    --namespace "$namespace" exec "$source_pod" -- \
    sh -ec 'cat /workspace/apps/dms/.env; printf x')
  environment_payload=${environment_payload%x}
fi

test -n "$environment_payload" || {
  echo "environment file is empty" >&2
  exit 1
}

printf '%s' "$environment_payload" | \
  kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
    create secret generic "$secret_name" \
    --from-file=dms.env=/dev/stdin \
    --dry-run=client --output=yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

unset environment_payload

kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  label secret "$secret_name" \
  app.kubernetes.io/name=frontend-dms-environment \
  app.kubernetes.io/part-of=coder \
  --overwrite >/dev/null

kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  get secret "$secret_name" \
  --output=custom-columns='NAME:.metadata.name,TYPE:.type,CREATED:.metadata.creationTimestamp'
