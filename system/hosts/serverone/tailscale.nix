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

  # For samba we have to run `tailscale serve --bg --tcp 445 tcp://localhost:445`
  # otherwise it samba will refuse the connections coming from tailscale0 interface.
  # The command needs to be run just once, then it saves this config to /var/lib/tailscale/tailscaled.state
  # which is some weird json-base64 thing.
  # TODO: find a way to automate this

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
