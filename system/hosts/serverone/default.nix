{
  flakeInputs,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    flakeInputs.disko.nixosModules.disko
    ./disko.nix

    ./users.nix

    ./containers.nix
    ./samba.nix

    ./wireguard.nix

    ../../modules/power-management
    ../../modules/graphics/intel.nix
  ];

  # https://github.com/nix-community/disko/issues/581#issuecomment-2260602290
  boot.zfs.extraPools = [
    "hdd_pool"
    "ssd_pool"
  ];

  services = {
    openssh = {
      enable = true;
    };
  };

  networking = {
    hostId = "d3cb129c";
    hostName = "serverone";
    interfaces.enp2s0.wakeOnLan.enable = true;
  };
}
