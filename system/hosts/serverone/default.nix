{
  flakeInputs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    flakeInputs.disko.nixosModules.disko
    flakeInputs.nix-snapshotter.nixosModules.default
    ./disko.nix
    ./storage.nix

    ./users.nix

    ./containers.nix
    ./samba.nix

    ./wireguard.nix
    ../../modules/tailscale.nix

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

  services.tailscale = {
    extraSetFlags = [
      "--advertise-routes=10.0.1.0/24"
      "--advertise-exit-node"
    ];
    useRoutingFeatures = lib.mkForce "server";
  };
}
