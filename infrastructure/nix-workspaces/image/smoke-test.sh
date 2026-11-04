#!/usr/bin/env bash
# Remote commands intentionally expand variables inside the SSH session.
# shellcheck disable=SC2016
set -euo pipefail

image=${1:-homelab-nix-workspace:validation}
test_dir=$(mktemp -d)
container="nix-workspace-test-$$"
volume="nix-workspace-test-$$"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
  rm -rf "$test_dir"
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/key"
mkdir -p "$test_dir/keys/..data"
cp "$test_dir/key.pub" "$test_dir/keys/..data/authorized_keys"
chmod 0644 "$test_dir/keys/..data/authorized_keys"
ln -s ..data/authorized_keys "$test_dir/keys/authorized_keys"
# Match Kubernetes Secret mounts, whose parent fails OpenSSH StrictModes.
chmod 1777 "$test_dir/keys"
docker volume create "$volume" >/dev/null

start() {
  docker run -d --name "$container" \
    --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add SETGID --cap-add SETUID --cap-add SYS_CHROOT \
    --security-opt no-new-privileges \
    -p 127.0.0.1::2222 -e "WORKSPACE_PROFILE=$1" \
    -v "$volume:/workspace" \
    -v "$test_dir/keys:/run/keys:ro" \
    "$image" >/dev/null
  port=$(docker port "$container" 2222/tcp | sed 's/.*://')
  for _attempt in $(seq 1 30); do
    if ssh-keyscan -p "$port" 127.0.0.1 > "$test_dir/known_hosts" 2>/dev/null; then
      return
    fi
    sleep 1
  done
  docker logs "$container" >&2
  return 1
}
remote() {
  ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$test_dir/known_hosts" -o StrictHostKeyChecking=yes \
    -i "$test_dir/key" -p "$port" dev@127.0.0.1 "$@"
}

start frontend
remote 'set -eu; test "$(id -u)" = 1000; test "$(node --version)" = v24.13.0; test "$(pnpm --version)" = 12.3.4; opencode --version; nix --version; git --version; tmux -V; printf persistent > ~/projects/persistence-test; nix develop --offline /opt/workspace-flake#frontend --command node --version'
host_key=$(docker exec "$container" cat /workspace/ssh/ssh_host_ed25519_key.pub)
if ssh -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
  -o "UserKnownHostsFile=$test_dir/known_hosts" -o StrictHostKeyChecking=yes \
  -i "$test_dir/key" -p "$port" root@127.0.0.1 true 2>/dev/null; then
  echo 'Root SSH login unexpectedly succeeded' >&2
  exit 1
fi
docker rm -f "$container" >/dev/null
start frontend-pnpm11
remote 'set -eu; opencode --version; test "$(pnpm --version)" = 11.22.0; nix develop --offline /opt/workspace-flake#frontend-pnpm11 --command pnpm --version'
docker rm -f "$container" >/dev/null
start backend
test "$host_key" = "$(docker exec "$container" cat /workspace/ssh/ssh_host_ed25519_key.pub)"
remote 'set -eu; test "$(cat ~/projects/persistence-test)" = persistent; php -r '\''if (PHP_MAJOR_VERSION !== 8 || PHP_MINOR_VERSION !== 4) exit(1); foreach (["ctype", "fileinfo", "gd", "gnupg", "iconv", "intl", "json", "mbstring", "openssl", "simplexml", "soap", "pdo_pgsql", "xsl", "rdkafka"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "Missing $ext\n"); exit(1); } }'\''; composer --version; nix develop --offline /opt/workspace-flake#backend --command php --version'
echo 'PASS: OpenCode, frontend/backend tools, non-root SSH, root rejection, Nix shells, persistent files and host key'
