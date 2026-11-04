#!/bin/sh
set -eu

repository_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig_path=${KUBECONFIG:-"$repository_root/.local/kubeconfig"}
public_key=${1:-"$HOME/.ssh/id_ed25519.pub"}

if [ ! -s "$public_key" ]; then
  echo "SSH public key not found: $public_key" >&2
  exit 1
fi
ssh-keygen -l -f "$public_key" >/dev/null
if ! head -n 1 "$public_key" | grep -Eq '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-|sk-ssh-|sk-ecdsa-)'; then
  echo 'Supply an SSH public key, never a private key.' >&2
  exit 1
fi
kubectl --kubeconfig "$kubeconfig_path" apply \
  -f "$repository_root/infrastructure/nix-workspaces/namespace.yaml"
kubectl --kubeconfig "$kubeconfig_path" -n nix-workspaces \
  create secret generic dev-authorized-keys \
  --from-file="authorized_keys=$public_key" --dry-run=client -o yaml | \
  kubectl --kubeconfig "$kubeconfig_path" -n nix-workspaces apply -f -
