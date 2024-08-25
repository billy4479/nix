{ pkgs, ... }:
{
  imports = [
    ./browser
    ./btop.nix
    ./direnv.nix
    ./editor/nvim
    ./editor/vscodium
    ./games
    ./git.nix
    ./office.nix
    ./qimgv.nix
    ./shell
    ./spotify.nix
    ./terminals/kitty.nix
    ./terminals/konsole
    ./zathura.nix
  ];

  home.packages = with pkgs; [
    telegram-desktop
    discord
    joplin-desktop
    kate
    qbittorrent
    qalculate-gtk
    ark
    gimp
  ];

  programs.office = {
    enableLibreOffice = true;
    enableOnlyOffice = false; # TODO: this doesn't work wery well on nix..
  };

  programs.mpv.enable = true; # TODO: there are some interesting configs here
}
