{ ... }:
{
  imports = [
    # Include only a minimal set of applications
    ./modules/applications/btop.nix
    ./modules/applications/direnv.nix
    ./modules/applications/editor/nvim
    ./modules/applications/git.nix
    ./modules/applications/shell
    ./modules/applications/zellij.nix
  ];
}
