FROM nixos/nix:2.31.2@sha256:29fc5fe207f159ceb0143c25c19c774062fee02ce5eda118f3067547b3054894

# QEMU/Rosetta builds may need false; the running workspace keeps the default.
ARG NIX_BUILD_FILTER_SYSCALLS=true
COPY flake.nix flake.lock frontend.nix /opt/workspace-flake/
RUN export NIX_CONFIG="filter-syscalls = $NIX_BUILD_FILTER_SYSCALLS" \
    && nix --extra-experimental-features 'nix-command flakes' build \
      --no-update-lock-file /opt/workspace-flake#default --out-link /opt/tools \
    && nix --extra-experimental-features 'nix-command flakes' build \
      --no-update-lock-file /opt/workspace-flake#frontend --out-link /opt/frontend-tools \
    && nix --extra-experimental-features 'nix-command flakes' build \
      --no-update-lock-file /opt/workspace-flake#frontend-pnpm11 --out-link /opt/frontend-pnpm11-tools \
    && nix --extra-experimental-features 'nix-command flakes' build \
      --no-update-lock-file /opt/workspace-flake#backend --out-link /opt/backend-tools \
    && nix --extra-experimental-features 'nix-command flakes' build \
      --no-update-lock-file /opt/workspace-flake#home --out-link /opt/home-manager \
    && dotfiles_revision=$(nix --extra-experimental-features 'nix-command flakes' eval \
      --raw --no-update-lock-file /opt/workspace-flake#dotfilesRevision) \
    && /opt/tools/bin/git init /opt/dotfiles \
    && /opt/tools/bin/git -C /opt/dotfiles remote add origin https://github.com/TiborSuty/dotfiles.git \
    && /opt/tools/bin/git -C /opt/dotfiles fetch --depth=1 origin "$dotfiles_revision" \
    && /opt/tools/bin/git -C /opt/dotfiles checkout -b shared-development-tools FETCH_HEAD \
    && test "$(/opt/tools/bin/git -C /opt/dotfiles rev-parse HEAD)" = "$dotfiles_revision" \
    && printf '\ndev:x:1000:1000:Developer:/workspace/home:/opt/tools/bin/bash\n' >> /etc/passwd \
    && printf '\ndev:x:1000:\n' >> /etc/group \
    && printf '\ndev:*:1:0:99999:7:::\n' >> /etc/shadow \
    && printf '\nsshd:x:998:998:SSH privilege separation:/var/empty:/bin/false\n' >> /etc/passwd \
    && printf '\nsshd:x:998:\n' >> /etc/group \
    && mkdir -p /var/empty /run/sshd /workspace /etc/ssh \
    && chmod 0755 /var/empty /run/sshd \
    && chown -R 1000:1000 /opt/dotfiles \
    && printf 'experimental-features = nix-command flakes\nbuild-users-group =\nsandbox = false\nmax-jobs = 2\n' > /etc/nix/nix.conf \
    && chown -R 1000:1000 /nix

# Keep agent installation in a separate layer while using the same locked Nixpkgs.
RUN nix --extra-experimental-features 'nix-command flakes' build \
    --no-update-lock-file --inputs-from /opt/workspace-flake \
    nixpkgs#opencode --out-link /opt/opencode-tools

ENV PATH=/opt/opencode-tools/bin:/opt/tools/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin \
    NIX_REMOTE=local \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt \
    TERM=xterm-256color

# Realise the shell environments during the image build as the workspace user.
# An SSH session can then enter either shell without fetching build inputs.
USER 1000:1000
RUN export NIX_CONFIG="filter-syscalls = $NIX_BUILD_FILTER_SYSCALLS" \
    && XDG_CACHE_HOME=/tmp/nix-cache nix print-dev-env /opt/workspace-flake#frontend >/dev/null \
    && XDG_CACHE_HOME=/tmp/nix-cache nix print-dev-env /opt/workspace-flake#frontend-pnpm11 >/dev/null \
    && XDG_CACHE_HOME=/tmp/nix-cache nix print-dev-env /opt/workspace-flake#backend >/dev/null
USER 0:0

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/workspace-entrypoint
COPY activate-home.sh /usr/local/bin/workspace-activate-home
RUN chmod 0755 /usr/local/bin/workspace-entrypoint /usr/local/bin/workspace-activate-home \
    && printf 'export PATH=/opt/opencode-tools/bin:/opt/tools/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin\nexport NIX_REMOTE=local\nexport NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt\n' > /etc/profile

EXPOSE 2222 3000
ENTRYPOINT ["/usr/local/bin/workspace-entrypoint"]
