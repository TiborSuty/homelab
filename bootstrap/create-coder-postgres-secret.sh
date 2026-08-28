#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
namespace=coder-system
secret_name=coder-postgres-credentials
rotate=false

case ${1:-} in
  "") ;;
  --rotate) rotate=true ;;
  *)
    echo "usage: $0 [--rotate]" >&2
    exit 1
    ;;
esac

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required" >&2
  exit 1
}

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required" >&2
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
  echo "Use --rotate to replace its password."
  exit 0
fi

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/coder-postgres-secret.XXXXXX")
cleanup() {
  unset database_password connection_uri
  if test -d "$temporary_directory"; then
    find "$temporary_directory" -type f -exec unlink {} \;
    rmdir "$temporary_directory"
  fi
}
trap cleanup 0
trap 'exit 1' 1 2 15

database_password=$(openssl rand -hex 32)
connection_uri="postgresql://coder:${database_password}@coder-postgres-rw.coder-system.svc.cluster.local:5432/coder"

umask 077
printf '%s' coder >"$temporary_directory/username"
printf '%s' "$database_password" >"$temporary_directory/password"
printf '%s' "$connection_uri" >"$temporary_directory/uri"

kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  create secret generic "$secret_name" \
  --type=kubernetes.io/basic-auth \
  --from-file=username="$temporary_directory/username" \
  --from-file=password="$temporary_directory/password" \
  --from-file=uri="$temporary_directory/uri" \
  --dry-run=client \
  --output=yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  label secret "$secret_name" cnpg.io/reload=true --overwrite >/dev/null

kubectl --kubeconfig "$kubeconfig_path" --namespace "$namespace" \
  get secret "$secret_name" \
  --output=custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp'
