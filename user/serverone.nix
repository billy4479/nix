{ ... }:
{
  imports = [
    # Include only a minimal set of applications
    ./modules/applications/btop.nix
    ./modules/applications/editor/nvim
    ./modules/applications/git.nix
    ./modules/applications/shell
  ];
}