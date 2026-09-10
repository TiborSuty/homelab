#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(dirname "$script_dir")
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
ca_path=${VAULTWARDEN_CA_FILE:-"$repository_root/.local/vaultwarden-ca.crt"}
vaultwarden_url=${VAULTWARDEN_URL:-"https://vaultwarden.vaultwarden.homelab.internal"}
namespace=vaultwarden
secret_name=vaultwarden-root-ca

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

if ! command -v security >/dev/null 2>&1; then
  echo "This helper currently supports the macOS keychain only" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to install bitwarden-cli" >&2
  exit 1
fi

if [ ! -f "$kubeconfig_path" ]; then
  echo "Kubeconfig not found: $kubeconfig_path" >&2
  exit 1
fi

install -d -m 700 "$(dirname "$ca_path")"

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" \
  get secret "$secret_name" \
  -o go-template='{{ index .data "tls.crt" | base64decode }}' >"$ca_path"
chmod 600 "$ca_path"

openssl x509 -in "$ca_path" -noout -checkend 86400 >/dev/null
ca_fingerprint=$(openssl x509 -in "$ca_path" -noout -fingerprint -sha256 | \
  sed 's/^.*=//; s/://g')
login_keychain=${VAULTWARDEN_KEYCHAIN:-"$HOME/Library/Keychains/login.keychain-db"}

if security find-certificate -a -Z "$login_keychain" 2>/dev/null | \
  grep -Fq "$ca_fingerprint"; then
  echo "Vaultwarden CA is already present in the login keychain."
else
  security add-trusted-cert -r trustRoot -k "$login_keychain" "$ca_path"
  echo "Trusted the Vaultwarden CA in the login keychain."
fi

if ! command -v bw >/dev/null 2>&1; then
  brew install bitwarden-cli
fi

bw config server "$vaultwarden_url" >/dev/null

echo "Bitwarden CLI server configured: $vaultwarden_url"
echo "The helper did not log in or store a master password/session key."
