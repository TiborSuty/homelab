{ dotfiles }:
{
  homeModule = {
    imports = [
      (dotfiles + "/nix/home/common.nix")
      (dotfiles + "/nix/home/workspace-vaultwarden.nix")
    ];
    home.username = "dev";
    home.homeDirectory = "/workspace/home";
    home.stateVersion = "26.05";
    targets.genericLinux.enable = true;
  };
  extraTools = pkgs: [ ];
  includeBackend = false;
}
