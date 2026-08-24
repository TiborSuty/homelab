#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
kubeconfig=${KUBECONFIG:-"$repo_dir/.local/kubeconfig"}
namespace=adguard-home
secret_name=adguard-home-admin

command -v kubectl >/dev/null 2>&1 || {
    echo "kubectl is required" >&2
    exit 1
}

command -v htpasswd >/dev/null 2>&1 || {
    echo "htpasswd with bcrypt support is required" >&2
    exit 1
}

test -r "$kubeconfig" || {
    echo "kubeconfig is not readable: $kubeconfig" >&2
    exit 1
}

export KUBECONFIG="$kubeconfig"

kubectl get namespace "$namespace" >/dev/null 2>&1 || \
    kubectl create namespace "$namespace" >/dev/null

kubectl label namespace "$namespace" \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/audit=restricted \
    pod-security.kubernetes.io/warn=restricted \
    --overwrite >/dev/null

if kubectl --namespace "$namespace" get secret "$secret_name" \
    >/dev/null 2>&1; then
    echo "Secret $namespace/$secret_name already exists."
    echo "Use the AdGuard Home UI to change the password after first boot."
    exit 0
fi

test -t 0 || {
    echo "an interactive terminal is required" >&2
    exit 1
}

hash_file=
temp_dir=
cleanup() {
    stty echo 2>/dev/null || true
    if test -n "${hash_file:-}" && test -f "$hash_file"; then
        unlink "$hash_file"
    fi
    if test -n "${temp_dir:-}" && test -d "$temp_dir"; then
        rmdir "$temp_dir"
    fi
}
trap cleanup 0
trap 'exit 1' 1 2 15

printf 'AdGuard Home admin password: ' >&2
stty -echo
IFS= read -r password
stty echo
printf '\nConfirm password: ' >&2
stty -echo
IFS= read -r password_confirm
stty echo
printf '\n' >&2

test -n "$password" || {
    echo "password must not be empty" >&2
    exit 1
}

test "${#password}" -ge 12 || {
    echo "password must contain at least 12 characters" >&2
    exit 1
}

test "$password" = "$password_confirm" || {
    echo "passwords do not match" >&2
    exit 1
}

password_hash=$(printf '%s\n' "$password" | htpasswd -niBC 12 admin | sed 's/^admin://')
unset password password_confirm

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/adguard-home-secret.XXXXXX")
hash_file="$temp_dir/passwordHash"
umask 077
printf '%s' "$password_hash" > "$hash_file"
unset password_hash

kubectl --namespace "$namespace" create secret generic "$secret_name" \
    --from-file=passwordHash="$hash_file" \
    --dry-run=client \
    --output=yaml | kubectl apply -f -

kubectl --namespace "$namespace" get secret "$secret_name" \
    --output=custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp'
