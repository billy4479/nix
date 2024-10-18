{ extraConfig, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management
    ../../modules/desktops
  ];

  networking.hostName = "portatilo";

  users.users.${extraConfig.user.username}.openssh.authorizedKeys.keys = [
    (builtins.readFile ../../../secrets/public_keys/billy_computerone.pub)
  ];
}
