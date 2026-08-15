#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
credentials_path=${GRAFANA_CREDENTIALS_FILE:-"$repository_root/.local/grafana.env"}
namespace=monitoring
secret_name=grafana-admin-credentials

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
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite >/dev/null

if kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" >/dev/null 2>&1; then
  if [ ! -f "$credentials_path" ]; then
    GRAFANA_ADMIN_USER=$(kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
      get secret "$secret_name" \
      -o go-template='{{ index .data "admin-user" | base64decode }}')
    GRAFANA_ADMIN_PASSWORD=$(kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
      get secret "$secret_name" \
      -o go-template='{{ index .data "admin-password" | base64decode }}')

    umask 077
    {
      printf 'GRAFANA_ADMIN_USER=%s\n' "$GRAFANA_ADMIN_USER"
      printf 'GRAFANA_ADMIN_PASSWORD=%s\n' "$GRAFANA_ADMIN_PASSWORD"
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
  GRAFANA_ADMIN_USER=admin
  GRAFANA_ADMIN_PASSWORD=$(openssl rand -hex 24)

  umask 077
  {
    printf 'GRAFANA_ADMIN_USER=%s\n' "$GRAFANA_ADMIN_USER"
    printf 'GRAFANA_ADMIN_PASSWORD=%s\n' "$GRAFANA_ADMIN_PASSWORD"
  } >"$credentials_path"
  chmod 600 "$credentials_path"
fi

: "${GRAFANA_ADMIN_USER:?GRAFANA_ADMIN_USER is missing from $credentials_path}"
: "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD is missing from $credentials_path}"

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret generic "$secret_name" \
  --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  >/dev/null

echo "Created Secret $namespace/$secret_name."
echo "Credentials are stored in $credentials_path (mode 600)."
