{
  description = "Tools shared by persistent Kubernetes development workspaces";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      toolsFor = pkgs: with pkgs; [
        bashInteractive coreutils curl findutils git gnugrep gnused gnutar
        gzip less neovim openssh procps ripgrep rsync tmux unzip which
      ];
      frontendFor = pkgs: import ./frontend.nix { inherit pkgs; };
      frontendPnpm11For = pkgs: import ./frontend.nix { inherit pkgs; pnpmVersion = "11.22.0"; };
      backendFor = pkgs:
        let php = pkgs.php84.buildEnv {
          extensions = { enabled, all }: enabled ++ (with all; [
            gd gnupg intl soap pdo_pgsql redis zip bcmath sockets xsl rdkafka
          ]);
          extraConfig = "memory_limit = -1";
        };
        in [ php (pkgs.php84.packages.composer.override { inherit php; }) ];
    in {
      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.buildEnv {
            name = "workspace-tools";
            paths = toolsFor pkgs;
            pathsToLink = [ "/bin" "/share" ];
          };
          frontend = pkgs.buildEnv {
            name = "frontend-tools";
            paths = frontendFor pkgs;
            pathsToLink = [ "/bin" ];
          };
          frontend-pnpm11 = pkgs.buildEnv {
            name = "frontend-pnpm11-tools";
            paths = frontendPnpm11For pkgs;
            pathsToLink = [ "/bin" ];
          };
          backend = pkgs.buildEnv {
            name = "backend-tools";
            paths = backendFor pkgs;
            pathsToLink = [ "/bin" ];
          };
        });
      devShells = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          default = pkgs.mkShell { packages = toolsFor pkgs; };
          frontend = pkgs.mkShell { packages = toolsFor pkgs ++ frontendFor pkgs; };
          frontend-pnpm11 = pkgs.mkShell { packages = toolsFor pkgs ++ frontendPnpm11For pkgs; };
          backend = pkgs.mkShell { packages = toolsFor pkgs ++ backendFor pkgs; };
        });
    };
}
