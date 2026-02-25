{
  pkgs,
  flakeInputs,
  extraConfig,
  ...
}:
let
  desktop = extraConfig.desktop;
in
{
  imports = [
    ../../modules/main-user.nix
    ../../modules/steam.nix
    ../../modules/sddm.nix
    ../../modules/sound.nix
  ]
  ++ (
    if desktop == "kde" then
      [ ./kde.nix ]
    else if desktop == "qtile" then
      [ ./qtile.nix ]
    else if desktop == "niri" then
      [ ./niri.nix ]
    else
      throw "desktop ${desktop} is not supported"
  );

  # It should help in desktop use
  # Mhh, it seems like it causes some crashes?
  # boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;
  boot.kernelPackages = pkgs.linuxPackages_zen;

  main-user = {
    enable = true;
    userName = extraConfig.user.username;
    fullName = extraConfig.user.fullName;
  };

  services = {
    gvfs.enable = true;
    udisks2.enable = true;
    printing.enable = true;
  };

  security.polkit.enable = true;

  environment.systemPackages = [ pkgs.android-tools ];

  programs = {
    # https://discourse.nixos.org/t/error-gdbus-error-org-freedesktop-dbus-error-serviceunknown-the-name-ca-desrt-dconf-was-not-provided-by-any-service-files/29111/2
    dconf.enable = true;
  };

  users.users.${extraConfig.user.username}.openssh = {
    authorizedKeys.keys = [
      (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
      (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_portatilo.pub")
      (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_nord.pub")
    ];
  };

}
