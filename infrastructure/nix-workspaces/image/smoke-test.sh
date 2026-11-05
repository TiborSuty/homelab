#!/usr/bin/env bash
# Remote commands intentionally expand variables inside the SSH session.
# shellcheck disable=SC2016
set -euo pipefail

image=${1:-homelab-nix-workspace:validation}
# Optionally test replacement of an older Home Manager-enabled image too.
previous_image=${2:-$image}
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

# The image must be self-contained when a new PVC is mounted. Existing
# unmanaged editor configuration must fail activation without losing data.
docker run --rm --network none --entrypoint /opt/tools/bin/bash "$image" -euc '
  install -d -o 1000 -g 1000 /workspace/home
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env HOME=/workspace/home USER=dev LOGNAME=dev \
    /opt/tools/bin/bash /usr/local/bin/workspace-activate-home
  test -L /workspace/home/.config/nvim
  test -x /workspace/home/.nix-profile/bin/nvim
'
docker run --rm --network none --entrypoint /opt/tools/bin/bash "$image" -euc '
  install -d -o 1000 -g 1000 /workspace/home /workspace/home/.config /workspace/home/.config/nvim
  printf "existing editor config\n" > /workspace/home/.config/nvim/init.lua
  chown 1000:1000 /workspace/home/.config/nvim/init.lua
  if setpriv --reuid=1000 --regid=1000 --clear-groups \
    env HOME=/workspace/home USER=dev LOGNAME=dev \
    /opt/tools/bin/bash /usr/local/bin/workspace-activate-home > /tmp/activation.log 2>&1; then
    echo "Unexpectedly replaced unmanaged Neovim configuration" >&2
    exit 1
  fi
  cat /tmp/activation.log
  grep -q "nvim.*would be clobbered" /tmp/activation.log
  test ! -L /workspace/home/.config/nvim
  test "$(cat /workspace/home/.config/nvim/init.lua)" = "existing editor config"
'

start() {
  docker run -d --name "$container" \
    --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add SETGID --cap-add SETUID --cap-add SYS_CHROOT \
    --security-opt no-new-privileges \
    -p 127.0.0.1::2222 -e "WORKSPACE_PROFILE=$1" \
    -v "$volume:/workspace" \
    -v "$test_dir/keys:/run/keys:ro" \
    "${2:-$image}" >/dev/null
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
  local -a terminal_args=()
  if [[ ${WORKSPACE_TEST_TTY:-0} == 1 ]]; then terminal_args=(-tt); fi
  ssh "${terminal_args[@]}" -F /dev/null -o BatchMode=yes -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=$test_dir/known_hosts" -o StrictHostKeyChecking=yes \
    -i "$test_dir/key" -p "$port" dev@127.0.0.1 "$@"
}

start frontend "$previous_image"
remote 'set -eu; test -L ~/.config/nvim; test -w ~/.config/nvim/lazy-lock.json; test "$(sha256sum < ~/.config/nvim/init.lua)" = "$(sha256sum < /opt/dotfiles/.config/nvim/init.lua)"; test "$(git -C ~/dotfiles rev-parse HEAD)" = "$(git -C /opt/dotfiles rev-parse HEAD)"; for tool in nvim git lazygit tmux rg fd fzf; do command -v "$tool"; done; nvim --headless -u NONE "+lua assert(vim.fn.stdpath(\"config\") == vim.env.HOME .. \"/.config/nvim\")" +qa; printf "# persistent shell marker\n" > ~/.bashrc; printf "# persistent profile marker\n" > ~/.bash_profile; printf "\n-- persistent editor marker\n" >> ~/dotfiles/.config/nvim/init.lua'
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
remote 'docker --version; docker compose version; docker buildx version'
remote 'command -v bw; command -v with_dev_secrets'
remote 'aws --version; AWS_PAGER= aws configure list-profiles'
remote 'cat > /tmp/check-vaultwarden.zsh' < "$(dirname "$0")/check-vaultwarden.zsh"
remote 'zsh -f /tmp/check-vaultwarden.zsh'
remote 'cat > /tmp/check-nx.sh' < "$(dirname "$0")/check-nx.sh"
remote 'nx_package=$(dirname "$(dirname "$(readlink -f "$(command -v nx)")")"); bash /tmp/check-nx.sh "$nx_package"'
remote 'cat > /tmp/check-zsh.zsh' < "$(dirname "$0")/check-zsh.zsh"
WORKSPACE_TEST_TTY=1 remote 'test "$SHELL" = /opt/tools/bin/zsh; zsh -lic "source /tmp/check-zsh.zsh"'
remote 'set -eu; tree-sitter --version; grep -q "persistent shell marker" ~/.bashrc; grep -q "persistent profile marker" ~/.bash_profile; grep -q "persistent editor marker" ~/.config/nvim/init.lua; test -w ~/.config/nvim/lazy-lock.json; test -x ~/.nix-profile/bin/nvim'
remote 'set -eu; opencode --version; test "$(pnpm --version)" = 11.22.0; nix develop --offline /opt/workspace-flake#frontend-pnpm11 --command pnpm --version'
docker rm -f "$container" >/dev/null
start backend
test "$host_key" = "$(docker exec "$container" cat /workspace/ssh/ssh_host_ed25519_key.pub)"
remote 'set -eu; test "$(cat ~/projects/persistence-test)" = persistent; php -r '\''if (PHP_MAJOR_VERSION !== 8 || PHP_MINOR_VERSION !== 4) exit(1); foreach (["ctype", "fileinfo", "gd", "gnupg", "iconv", "intl", "json", "mbstring", "openssl", "simplexml", "soap", "pdo_pgsql", "xsl", "rdkafka"] as $ext) { if (!extension_loaded($ext)) { fwrite(STDERR, "Missing $ext\n"); exit(1); } }'\''; composer --version; nix develop --offline /opt/workspace-flake#backend --command php --version'
echo 'PASS: shared Home Manager tools, writable Neovim configuration, preserved editor/shell changes, OpenCode, frontend/backend tools, non-root SSH, root rejection, Nix shells, persistent files and host key'
