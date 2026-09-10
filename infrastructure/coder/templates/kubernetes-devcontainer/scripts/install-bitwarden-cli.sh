#!/bin/sh

set -eu

version=2026.8.0
architecture=$(uname -m)

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

wget -qO "$archive_path" "$download_url"
printf '%s  %s\n' "$archive_sha256" "$archive_path" | sha256sum -c -
unzip -q "$archive_path" -d /tools
chmod 0755 /tools/bw
