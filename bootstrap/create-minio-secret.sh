#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
credentials_path=${MINIO_CREDENTIALS_FILE:-"$repository_root/.local/minio.env"}
namespace=minio
secret_name=minio-root-credentials

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

install -d -m 700 "$(dirname "$credentials_path")"

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" \
  >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig_path" create namespace "$namespace"

kubectl --kubeconfig "$kubeconfig_path" label namespace "$namespace" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite >/dev/null

if kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" >/dev/null 2>&1; then
  if [ ! -f "$credentials_path" ]; then
    minio_root_user=$(kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
      get secret "$secret_name" \
      -o go-template='{{ index .data "MINIO_ROOT_USER" | base64decode }}')
    minio_root_password=$(kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
      get secret "$secret_name" \
      -o go-template='{{ index .data "MINIO_ROOT_PASSWORD" | base64decode }}')

    umask 077
    {
      printf 'MINIO_ROOT_USER=%s\n' "$minio_root_user"
      printf 'MINIO_ROOT_PASSWORD=%s\n' "$minio_root_password"
    } >"$credentials_path"
    chmod 600 "$credentials_path"
  fi

  echo "Secret $namespace/$secret_name already exists."
  echo "Credentials are stored in $credentials_path (mode 600)."
  exit 0
fi

if [ -f "$credentials_path" ]; then
  # The generated file contains only shell-safe alphanumeric values.
  # shellcheck disable=SC1090
  . "$credentials_path"
else
  MINIO_ROOT_USER=minio-root
  MINIO_ROOT_PASSWORD=$(openssl rand -hex 24)

  umask 077
  {
    printf 'MINIO_ROOT_USER=%s\n' "$MINIO_ROOT_USER"
    printf 'MINIO_ROOT_PASSWORD=%s\n' "$MINIO_ROOT_PASSWORD"
  } >"$credentials_path"
  chmod 600 "$credentials_path"
fi

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is missing from $credentials_path}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is missing from $credentials_path}"

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret generic "$secret_name" \
  --from-literal=MINIO_ROOT_USER="$MINIO_ROOT_USER" \
  --from-literal=MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
  >/dev/null

echo "Created Secret $namespace/$secret_name."
echo "Credentials are stored in $credentials_path (mode 600)."
