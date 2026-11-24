{ dotfiles }:
{
  homeModule = dotfiles + "/nix/home/workspace.nix";
  extraTools = pkgs: with pkgs; [ docker-client awscli2 vault-bin ];
  includeBackend = true;
}
