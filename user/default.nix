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
    ./modules/scripts
    ./modules/secrets.nix
  ];

  home.stateVersion = "23.11";

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

  services.ssh-agent.enable = true;
  programs.ssh.addKeysToAgent = "yes";
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
