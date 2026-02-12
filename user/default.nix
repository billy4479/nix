{
  pkgs,
  lib,
  extraConfig,
  config,
  ...
}:
let
  public_key_name = "${extraConfig.user.username}_${extraConfig.hostname}.pub";
  public_key = ../secrets/public_keys/ssh/${public_key_name};
in
{
  home.username = extraConfig.user.username;
  home.homeDirectory = "/home/${extraConfig.user.username}";

  imports = [
    ./${extraConfig.hostname}.nix
    ./modules/secrets.nix
    ./modules/scripts
  ];

  home.stateVersion = "23.11";

  home.file."${config.home.homeDirectory}/.ssh/id_ed25519.pub" =
    lib.mkIf (builtins.pathExists public_key)
      {
        source = public_key;
      };

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.home-manager.enable = true;
  news.display = "silent";
}
