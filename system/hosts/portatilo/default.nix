{ extraConfig, flakeInputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management
    ../../modules/desktops

    ../../modules/cifs-client.nix
    ../../modules/wireguard.nix
    ../../modules/extra-network.nix
  ];

  networking.hostName = "portatilo";

  users.users.${extraConfig.user.username}.openssh.authorizedKeys.keys = [
    (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/billy_computerone.pub")
  ];
}
