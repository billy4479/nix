{
  lib,
  pkgs,
  ...
}:
let
  app = pkgs.callPackage ../../../packages/agent-vm { };
  sdk =
    ((pkgs.androidenv.composeAndroidPackages.override { licenseAccepted = true; }) {
      includeEmulator = true;
      emulatorVersion = "37.3.9";
      includeSystemImages = true;
      systemImageTypes = [ "default" ];
      platformVersions = [ "35" ];
      abiVersions = [ "x86_64" ];
      buildToolsVersions = [ ];
      includeCmake = false;
    }).androidsdk;
  state = "/mnt/SSD/agent-vm/android";
  ns = "agent-android";
  link = "agentandr0";
  host = "10.231.87.5";
  guest = "10.231.87.6";
  uplink = "enp2s0";
in
{
  system.build.agentAndroidSdk = sdk;
  users.groups.agent-android = { };
  users.users.agent-android = {
    isSystemUser = true;
    group = "agent-android";
    extraGroups = [ "kvm" ];
  };

  # The emulator's user-mode NAT originates connections here, not from the
  # existing libvirt bridge. Its namespace has no host services on loopback.
  networking.firewall.extraForwardRules = lib.mkAfter ''
    iifname "${link}" oifname "${uplink}" ip saddr ${guest} accept
  '';
  networking.nftables.tables.agent-android = {
    family = "inet";
    content = # nftables
      ''
        set nonpublic {
          type ipv4_addr; flags interval;
          elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
                       169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24,
                       192.0.2.0/24, 192.88.99.0/24, 192.168.0.0/16,
                       198.18.0.0/15, 198.51.100.0/24, 203.0.113.0/24,
                       224.0.0.0/3 }
        }
        chain input {
          type filter hook input priority filter - 5; policy accept;
          iifname "${link}" drop
        }
        chain output {
          type filter hook output priority filter - 5; policy accept;
          oifname "${link}" drop
        }
        chain forward {
          type filter hook forward priority filter - 5; policy accept;
          iifname "${link}" ip daddr @nonpublic drop
          iifname "${link}" ct status dnat drop
          iifname "${link}" oifname "${uplink}" ip saddr ${guest} ct direction original ct state { new, established } accept
          iifname "${link}" drop
          oifname "${link}" iifname "${uplink}" ip daddr ${guest} ct direction reply ct state { established, related } accept
          oifname "${link}" drop
        }
        chain nat {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${uplink}" ip saddr ${guest} masquerade
        }
      '';
  };

  systemd.services.agent-android-network = {
    description = "Private network namespace for the Android emulator";
    bindsTo = [ "nftables.service" ];
    after = [ "nftables.service" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = # sh
      ''
        ip netns add ${ns}
        trap 'ip netns delete ${ns}' EXIT
        ip link add ${link} type veth peer name eth0 netns ${ns}
        ip address add ${host}/30 dev ${link}
        ip link set ${link} up
        ip -n ${ns} link set lo up
        ip -n ${ns} address add ${guest}/30 dev eth0
        ip -n ${ns} link set eth0 up
        ip -n ${ns} route add default via ${host}
        trap - EXIT
      '';
    preStop = # sh
      ''
        ip netns delete ${ns}
      '';
  };

  systemd.services.agent-android = {
    description = "Lease-scoped, headless Android emulator";
    requires = [ "agent-vm-storage.service" ];
    bindsTo = [ "agent-android-network.service" ];
    after = [
      "agent-vm-storage.service"
      "agent-android-network.service"
    ];
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      User = "agent-android";
      Group = "agent-android";
      NetworkNamespacePath = "/run/netns/${ns}";
      RuntimeDirectory = "agent-android";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0700 -o agent-android -g agent-android ${state}";
      ExecStart = "${lib.getExe app} run-emulator --state ${state} --sdk ${sdk}/libexec/android-sdk";
      TimeoutStartSec = 125;
      TimeoutStopSec = 10;
      KillMode = "control-group";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/mnt/SSD/agent-vm" ];
      NoNewPrivileges = true;
      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/kvm rw" ];
      MemoryMax = "4G";
    };
  };
}
