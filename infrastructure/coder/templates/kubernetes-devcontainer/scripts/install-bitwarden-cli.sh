#!/bin/sh

set -eu

version=2026.8.0
stow_version=2.4.1
architecture=$(uname -m)
workspace_volume=${WORKSPACE_VOLUME:-/workspace-volume}
source_root=${SOURCE_ROOT:-/source}
install_dir="$workspace_volume/.coder-tools/bin"
share_dir="$workspace_volume/.coder-tools/share"
libexec_dir="$workspace_volume/.coder-tools/libexec"
perl_lib_dir="$workspace_volume/.coder-tools/lib/perl5"
secret_dir="$workspace_volume/.coder-secrets"

download() {
  destination=$1
  url=$2
  attempt=1

  while [ "$attempt" -le 3 ]; do
    if command -v wget >/dev/null 2>&1; then
      wget -O "$destination" "$url" && return 0
    elif command -v curl >/dev/null 2>&1; then
      curl -fsSLo "$destination" "$url" && return 0
    else
      echo "Neither wget nor curl is available to download workspace tools." >&2
      return 1
    fi

    echo "Download attempt $attempt failed: $url" >&2
    rm -f "$destination"
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done

  return 1
}

case "$architecture" in
  x86_64 | amd64)
    archive_name="bw-linux-$version.zip"
    archive_sha256=367f618e9fcccaac4980ec12c7bafd01df739b5f3cb1af31bc9045cf75eea1d6
    ;;
  aarch64 | arm64)
    archive_name="bw-linux-arm64-$version.zip"
    archive_sha256=74d822a5dceda5896ed8fc07bc61925b29afd98d96a6a3e9e525ae556c3083a8
    ;;
  *)
    echo "Unsupported Bitwarden CLI architecture: $architecture" >&2
    exit 1
    ;;
esac

archive_path=/tmp/bitwarden-cli.zip
download_url="https://github.com/bitwarden/clients/releases/download/cli-v$version/$archive_name"
stow_archive_path=/tmp/stow.tar.gz
stow_download_url="https://ftp.gnu.org/gnu/stow/stow-$stow_version.tar.gz"
stow_fallback_url="https://ftpmirror.gnu.org/stow/stow-$stow_version.tar.gz"
stow_archive_sha256=2a671e75fc207303bfe86a9a7223169c7669df0a8108ebdf1a7fe8cd2b88780b
stow_source_dir="/tmp/stow-$stow_version"

mkdir -p "$install_dir" "$share_dir" "$libexec_dir" "$perl_lib_dir/Stow"
rm -f \
  "$install_dir/bw" \
  "$install_dir/stow" \
  "$libexec_dir/stow" \
  "$perl_lib_dir/Stow.pm" \
  "$perl_lib_dir/Stow/Util.pm" \
  "$share_dir/vaultwarden-ca.crt" \
  "$secret_dir/dms.env"
download "$archive_path" "$download_url"
printf '%s  %s\n' "$archive_sha256" "$archive_path" | sha256sum -c -
unzip -q -o "$archive_path" -d "$install_dir"
chmod 0755 "$install_dir/bw"

download "$stow_archive_path" "$stow_download_url" || \
  download "$stow_archive_path" "$stow_fallback_url"
printf '%s  %s\n' "$stow_archive_sha256" "$stow_archive_path" | sha256sum -c -
tar --no-same-owner -xzf "$stow_archive_path" -C /tmp
sed \
  -e '1s|.*|#!/usr/bin/env perl|' \
  -e "s/@VERSION@/$stow_version/g" \
  -e '/@USE_LIB_PMDIR@/d' \
  "$stow_source_dir/bin/stow.in" >"$libexec_dir/stow"
sed "s/@VERSION@/$stow_version/g" \
  "$stow_source_dir/lib/Stow.pm.in" >"$perl_lib_dir/Stow.pm"
sed "s/@VERSION@/$stow_version/g" \
  "$stow_source_dir/lib/Stow/Util.pm.in" >"$perl_lib_dir/Stow/Util.pm"
cat >"$install_dir/stow" <<'EOF'
#!/bin/sh
set -eu

tool_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export PERL5LIB="$tool_root/lib/perl5${PERL5LIB:+:$PERL5LIB}"
exec perl "$tool_root/libexec/stow" "$@"
EOF
chmod 0755 "$install_dir/stow" "$libexec_dir/stow"

cp "$source_root/vaultwarden/ca.crt" "$share_dir/vaultwarden-ca.crt"
chmod 0444 "$share_dir/vaultwarden-ca.crt"

if [ -f "$source_root/frontend-dms/dms.env" ]; then
  mkdir -p "$secret_dir"
  cp "$source_root/frontend-dms/dms.env" "$secret_dir/dms.env"
  chmod 0600 "$secret_dir/dms.env"
fi
