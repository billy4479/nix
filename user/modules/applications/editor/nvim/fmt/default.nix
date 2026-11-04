{ config, pkgs, ... }:
{
  home.packages = [
    (pkgs.callPackage ./package.nix {
      # The exact nvim build the interactive editor uses, so `fmt` runs
      # against the same config and plugins.
      neovim = config.programs.neovim.finalPackage;
    })
  ];
}
