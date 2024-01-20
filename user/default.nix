{
  config,
  pkgs,
  extraConfig,
  ...
}: {
  home.username = extraConfig.user.username;
  home.homeDirectory = "/home/${extraConfig.user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

  imports =
    [
      ./applications/browser
      ./applications/btop.nix
      ./applications/direnv.nix
      ./applications/editor/nvim
      ./applications/editor/vscodium
      ./applications/git.nix
      ./applications/shell
      ./applications/spotify.nix
      ./applications/terminals/kitty.nix
      ./applications/terminals/konsole
      ./applications/zathura.nix
      ./cursor.nix
      ./fonts
      ./gtk.nix
      ./xdg-open.nix

      ./wallpapers.nix

      (import ./desktops extraConfig.desktop)
      ./applications/office.nix
    ]
    ++ (
      if extraConfig.desktop != "kde"
      then [./qt.nix]
      else []
    );

  home.stateVersion = "23.11";

  catppuccin = {inherit (extraConfig.catppuccinColors) flavour accent;};

  programs.office = {
    enableLibreOffice = true;
    enableOnlyOffice = true;
  };

  home.packages = with pkgs; [
    # Shell utilities, not fundamental but still nice
    fd
    ripgrep
    p7zip
    license-cli
    bat-extras.batman

    # GUI stuff
    telegram-desktop
    discord
    joplin-desktop
    kate
    qbittorrent
    qalculate-gtk
    ark

    gcc
  ];

  xsession.numlock.enable = !extraConfig.wayland;

  programs.mpv.enable = true; # TODO: there are some interesting configs here

  home.file = {};

  home.sessionVariables = {
    EDITOR = "nvim";

    # https://github.com/doron-cohen/antidot/blob/master/rules.yaml#L328
    GTK2_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
  };

  programs.home-manager.enable = true;
}
