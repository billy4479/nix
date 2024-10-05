{
  pkgs,
  extraConfig,
  config,
  ...
}:
{
  home.username = extraConfig.user.username;
  home.homeDirectory = "/home/${extraConfig.user.username}";

  # Enable unfree - yes, we have to do this here too
  nixpkgs.config.allowUnfree = true;

  imports = [
    ./applications
    ./cursor.nix
    ./fonts
    ./gtk.nix
    ./scripts
    ./secrets.nix
    ./services/syncthing.nix
    ./xdg-open.nix

    ./wallpapers.nix

    (import ./desktops extraConfig.desktop)
  ] ++ (if extraConfig.desktop != "kde" then [ ./qt.nix ] else [ ]);

  home.stateVersion = "23.11";

  catppuccin = {
    inherit (extraConfig.catppuccinColors) flavor accent;
  };

  home.packages = with pkgs; [
    # Shell utilities, not fundamental but still nice
    fd
    ripgrep
    p7zip
    zip
    license-cli
    bat-extras.batman
    jq
  ];

  xsession.numlock.enable = !extraConfig.wayland;

  home.file."${config.home.homeDirectory}/.ssh/id_ed25519.pub".source = ./keys/computerone.pub;

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
}
