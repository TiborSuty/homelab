#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
credentials_path=${REGISTRY_CREDENTIALS_FILE:-"$repository_root/.local/registry.env"}
ca_key_path=${REGISTRY_CA_KEY_FILE:-"$repository_root/.local/registry-ca.key"}
ca_certificate_path="$repository_root/talos/registry-ca.crt"
namespace=registry
auth_secret_name=zot-auth
ca_secret_name=registry-ca
pull_secret_name=registry-pull
registry_host=registry.homelab.internal

for command_name in kubectl openssl htpasswd; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required" >&2
    exit 1
  fi
done

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

install -d -m 700 "$(dirname "$credentials_path")"
install -d -m 700 "$(dirname "$ca_key_path")"

if [ -f "$ca_key_path" ] && [ ! -f "$ca_certificate_path" ]; then
  echo "Registry CA key exists but public certificate is missing." >&2
  echo "Refusing to generate a mismatched certificate." >&2
  exit 1
fi

if [ ! -f "$ca_key_path" ] && [ -f "$ca_certificate_path" ]; then
  echo "Registry public CA exists but its private key is missing." >&2
  echo "Restore $ca_key_path or rotate the registry CA deliberately." >&2
  exit 1
fi

if [ ! -f "$ca_key_path" ]; then
  umask 077
  openssl ecparam -name prime256v1 -genkey -noout -out "$ca_key_path"
  openssl req -x509 -new -sha256 -days 3650 \
    -key "$ca_key_path" \
    -subj "/CN=Tibor Suty Homelab Registry CA/O=Tibor Suty Homelab" \
    -out "$ca_certificate_path"
  chmod 600 "$ca_key_path"
  chmod 644 "$ca_certificate_path"
fi

if [ -f "$credentials_path" ]; then
  # Values are generated as shell-safe hexadecimal strings.
  # shellcheck disable=SC1090
  . "$credentials_path"
else
  REGISTRY_ADMIN_USERNAME=registry-admin
  REGISTRY_ADMIN_PASSWORD=$(openssl rand -hex 24)
  REGISTRY_PUSH_USERNAME=loky-ci-push
  REGISTRY_PUSH_PASSWORD=$(openssl rand -hex 24)
  REGISTRY_PULL_USERNAME=loky-cluster-pull
  REGISTRY_PULL_PASSWORD=$(openssl rand -hex 24)

  umask 077
  {
    printf 'REGISTRY_ADMIN_USERNAME=%s\n' "$REGISTRY_ADMIN_USERNAME"
    printf 'REGISTRY_ADMIN_PASSWORD=%s\n' "$REGISTRY_ADMIN_PASSWORD"
    printf 'REGISTRY_PUSH_USERNAME=%s\n' "$REGISTRY_PUSH_USERNAME"
    printf 'REGISTRY_PUSH_PASSWORD=%s\n' "$REGISTRY_PUSH_PASSWORD"
    printf 'REGISTRY_PULL_USERNAME=%s\n' "$REGISTRY_PULL_USERNAME"
    printf 'REGISTRY_PULL_PASSWORD=%s\n' "$REGISTRY_PULL_PASSWORD"
  } >"$credentials_path"
  chmod 600 "$credentials_path"
fi

: "${REGISTRY_ADMIN_USERNAME:?REGISTRY_ADMIN_USERNAME is missing}"
: "${REGISTRY_ADMIN_PASSWORD:?REGISTRY_ADMIN_PASSWORD is missing}"
: "${REGISTRY_PUSH_USERNAME:?REGISTRY_PUSH_USERNAME is missing}"
: "${REGISTRY_PUSH_PASSWORD:?REGISTRY_PUSH_PASSWORD is missing}"
: "${REGISTRY_PULL_USERNAME:?REGISTRY_PULL_USERNAME is missing}"
: "${REGISTRY_PULL_PASSWORD:?REGISTRY_PULL_PASSWORD is missing}"

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/zot-auth.XXXXXX")
auth_file="$temp_dir/htpasswd"

cleanup() {
  unset REGISTRY_ADMIN_PASSWORD REGISTRY_PUSH_PASSWORD REGISTRY_PULL_PASSWORD
  if [ -f "$auth_file" ]; then
    unlink "$auth_file"
  fi
  if [ -d "$temp_dir" ]; then
    rmdir "$temp_dir"
  fi
}
trap cleanup 0
trap 'exit 1' 1 2 15

umask 077
printf '%s\n' "$REGISTRY_ADMIN_PASSWORD" | \
  htpasswd -niBC 12 "$REGISTRY_ADMIN_USERNAME" >"$auth_file"
printf '%s\n' "$REGISTRY_PUSH_PASSWORD" | \
  htpasswd -niBC 12 "$REGISTRY_PUSH_USERNAME" >>"$auth_file"
printf '%s\n' "$REGISTRY_PULL_PASSWORD" | \
  htpasswd -niBC 12 "$REGISTRY_PULL_USERNAME" >>"$auth_file"

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" \
  >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig_path" create namespace "$namespace" \
    >/dev/null

kubectl --kubeconfig "$kubeconfig_path" label namespace "$namespace" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite >/dev/null

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret tls "$ca_secret_name" \
  --cert="$ca_certificate_path" \
  --key="$ca_key_path" \
  --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret generic "$auth_secret_name" \
  --from-file=htpasswd="$auth_file" \
  --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  create secret docker-registry "$pull_secret_name" \
  --docker-server="$registry_host" \
  --docker-username="$REGISTRY_PULL_USERNAME" \
  --docker-password="$REGISTRY_PULL_PASSWORD" \
  --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null

echo "Created or updated registry Secrets in namespace $namespace."
echo "Credentials: $credentials_path (mode 600)."
echo "Private CA key: $ca_key_path (mode 600)."
echo "Public CA certificate: $ca_certificate_path."
