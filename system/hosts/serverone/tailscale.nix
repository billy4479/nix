{ pkgs, lib, ... }:
{
  imports = [
    ../../modules/tailscale.nix
  ];
  services.tailscale = {
    useRoutingFeatures = lib.mkForce "server";
    extraSetFlags = [
      "--advertise-exit-node"
    ];
  };

  systemd.services.transport-layer-offloads = {
    # https://tailscale.com/kb/1319/performance-best-practices#ethtool-configuration.
    description = "Transport layer offloads for UDP";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ethtool}/sbin/ethtool -K enp2s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
    wantedBy = [ "default.target" ];
  };

}
