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
    ./ssh.nix

    flakeInputs.nix-snapshotter.nixosModules.default
    ./containers.nix
    ./samba.nix

    ./monitoring.nix

    ../../modules/smartd.nix
    ../../modules/zfs-scrub-notify.nix
    ../../modules/tailscale.nix

    ../../modules/power-management
    ../../modules/graphics/intel.nix
  ];

  # SMART failures are reported through smartctl_exporter -> Alertmanager;
  # maintenance pings (long self-test and scrub start/finish) go straight
  # to Telegram instead.
  services.smartd.telegramNotify.enable = false;
  services.smartd.longTestNotify.enable = true;
  services.zfs.scrubTelegramNotify.enable = true;

  networking = {
    hostId = "d3cb129c";
    hostName = "serverone";
    interfaces.enp2s0.wakeOnLan.enable = true;
  };

  services.tailscale = {
    extraSetFlags = [
      "--advertise-routes=10.0.1.0/24"
      "--advertise-exit-node"
      # Preserve client source IPs for subnet-routed traffic: tsidp's WhoIs
      # (X-Real-IP through nginx) needs real 100.64.0.0/10 addresses, and the
      # generated nginx ACLs rely on them to tell tailnet clients apart from
      # LAN ones. Reply traffic flows back via conntrack and the FORWARD
      # rules in containers.nix.
      "--snat-subnet-routes=false"
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
