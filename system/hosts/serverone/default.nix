{
  flakeInputs,
  lib,
  pkgs,
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

  systemd.services.tailscaled-autoconnect = {
    wants = [ "nerdctl-headscale.service" ];
    after = [ "nerdctl-headscale.service" ];
  };

  systemd.services.tailscale-ethtool = {
    description = "Configure NIC offloads for Tailscale subnet routing";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-enp2s0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-enp2s0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K enp2s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };
}
