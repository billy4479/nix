{
  flakeInputs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    flakeInputs.disko.nixosModules.disko
    ./disko.nix
    {
      disko.devices.disk = import "${flakeInputs.secrets-repo}/serverone-disks.nix";
    }
    ./storage.nix

    ./users.nix

    flakeInputs.nix-snapshotter.nixosModules.default
    ./containers.nix
    ./samba.nix

    ../../modules/smartd.nix
    ../../modules/tailscale.nix

    ../../modules/power-management
    ../../modules/graphics/intel.nix
  ];

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
