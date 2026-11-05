#!/usr/bin/env bash
set -euo pipefail

# Run as dev, after /workspace is mounted. All Git objects are in the image;
# first boot and subsequent activations require no network access.
if [[ ! -e "$HOME/dotfiles" && ! -L "$HOME/dotfiles" ]]; then
  git clone --no-hardlinks /opt/dotfiles "$HOME/dotfiles"
  git -C "$HOME/dotfiles" remote set-url origin https://github.com/TiborSuty/dotfiles.git
fi

if [[ ! -f "$HOME/dotfiles/.config/nvim/init.lua" ]]; then
  echo 'Expected ~/dotfiles/.config/nvim/init.lua; existing dotfiles were left untouched.' >&2
  exit 1
fi

# Do not reset/pull an existing checkout: it may contain personal edits or
# plugin lockfile changes. Home Manager likewise refuses unmanaged conflicts.
exec /opt/home-manager/activate
