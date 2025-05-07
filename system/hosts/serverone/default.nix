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
    ./storage.nix

    ./users.nix

    ./containers.nix
    ./samba.nix

    ./wireguard.nix

    ../../modules/power-management
    ../../modules/graphics/intel.nix
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
