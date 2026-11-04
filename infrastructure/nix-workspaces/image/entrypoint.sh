#!/bin/sh
set -eu

case "${WORKSPACE_PROFILE:-default}" in
  frontend|frontend-pnpm11|backend) project_bin="/opt/${WORKSPACE_PROFILE}-tools/bin:" ;;
  default) WORKSPACE_PROFILE=default; project_bin= ;;
  *) echo 'Unknown WORKSPACE_PROFILE' >&2; exit 1 ;;
esac
export PATH="${project_bin}/opt/tools/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
printf 'export PATH=%s\nexport NIX_REMOTE=local\nexport NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt\nexport WORKSPACE_PROFILE=%s\n' \
  "$PATH" "$WORKSPACE_PROFILE" > /etc/profile

if [ ! -s /run/keys/authorized_keys ]; then
  echo 'Mount a non-empty authorized_keys file at /run/keys/authorized_keys.' >&2
  exit 1
fi
install -m 0644 /run/keys/authorized_keys /etc/ssh/workspace_authorized_keys

# Never recursively chown an existing workspace on restart.
mkdir -p /workspace/home /workspace/home/projects /workspace/ssh /run/sshd
chown 1000:1000 /workspace/home /workspace/home/projects
chmod 0700 /workspace/home /workspace/ssh
if [ ! -f /workspace/ssh/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N '' -f /workspace/ssh/ssh_host_ed25519_key
fi
chmod 0600 /workspace/ssh/ssh_host_ed25519_key
sshd -t -f /etc/ssh/sshd_config
exec /opt/tools/bin/sshd -D -e -f /etc/ssh/sshd_config \
  -o "SetEnv=PATH=$PATH NIX_REMOTE=local NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt WORKSPACE_PROFILE=$WORKSPACE_PROFILE"
