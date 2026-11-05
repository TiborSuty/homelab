{
  description = "Tools shared by persistent Kubernetes development workspaces";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  # Match the Mac's independently pinned Bitwarden CLI package set.
  inputs.nixpkgs-bitwarden.url = "github:NixOS/nixpkgs/5c9de89ec55bff981cb8da1a4ee92b10f1438ffc";
  inputs.home-manager = {
    url = "github:nix-community/home-manager/24f2190587513b9c2f73db112a17844ae912d965";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.dotfiles = {
    url = "github:TiborSuty/dotfiles/shared-development-tools";
    flake = false;
  };

  outputs = { self, nixpkgs, nixpkgs-bitwarden, home-manager, dotfiles }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      homeFor = pkgs: home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs.bitwardenPackage =
          nixpkgs-bitwarden.legacyPackages.${pkgs.stdenv.hostPlatform.system}.bitwarden-cli;
        modules = [
          (dotfiles + "/nix/home/workspace.nix")
          {
            # The workspace is a CLI container, without a GPU or user systemd.
            targets.genericLinux.gpu.enable = false;
            systemd.user.enable = false;
          }
        ];
      };
      toolsFor = pkgs: with pkgs; [
        bashInteractive coreutils curl findutils gnugrep gnused gnutar
        gzip less openssh procps rsync unzip which util-linux
        # Includes the Compose and Buildx CLI plugins; the engine is external.
        docker-client
      ] ++ (homeFor pkgs).config.home.packages;
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
      # Used by the image build to bundle a matching, offline Git checkout.
      dotfilesRevision = dotfiles.rev;
      homeConfigurations = forAllSystems (system:
        homeFor (import nixpkgs { inherit system; }));
      packages = forAllSystems (system:
        let pkgs = import nixpkgs { inherit system; };
        in {
          home = (homeFor pkgs).activationPackage;
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
