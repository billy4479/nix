{
  config,
  flakeInputs,
  lib,
  pkgs,
  ...
}:
let
  app = pkgs.callPackage ../../../packages/agent-vm { };
  guest = flakeInputs.nixpkgs.lib.nixosSystem {
    modules = [ ./agent-vm-guest.nix ];
  };
  image = guest.config.system.build.agentVMImage;
  bridge = "agentvm0";
  ip = "10.231.87.2";
  uplink = "enp2s0";
  dataset = "ssd_pool/agent-vm";
  storage = "/mnt/SSD/agent-vm";
  runtime = "/run/agent-vm";
  args = "--storage ${storage} --base-image ${image}/nixos.qcow2 --guest-ip ${ip} --bridge ${bridge} --with-android";
in
{
  imports = [ ./agent-android.nix ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
    };
  };

  networking.bridges.${bridge}.interfaces = [ ];
  networking.interfaces.${bridge}.ipv4.addresses = [
    {
      address = "10.231.87.1";
      prefixLength = 30;
    }
  ];
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;
  networking.firewall.extraForwardRules = lib.mkAfter ''
    iifname "${bridge}" oifname "${uplink}" ip saddr ${ip} accept
  '';
  networking.nftables.tables.agent-vm = {
    family = "inet";
    content = # nftables
      ''
        set nonpublic {
          type ipv4_addr; flags interval;
          elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8,
                       169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.0.2.0/24,
                       192.88.99.0/24, 192.168.0.0/16, 198.18.0.0/15, 198.51.100.0/24,
                       203.0.113.0/24, 224.0.0.0/3 }
        }
        chain input {
          type filter hook input priority filter - 5; policy accept;
          iifname "${bridge}" ip saddr ${ip} tcp sport 22 ct state established ct direction reply accept
          iifname "${bridge}" drop
        }
        chain forward {
          type filter hook forward priority filter - 5; policy accept;
          iifname "${bridge}" ip daddr @nonpublic drop
          iifname "${bridge}" ct status dnat drop
          iifname "${bridge}" oifname "${uplink}" ip saddr ${ip} ct direction original ct state { new, established } accept
          iifname "${bridge}" drop
          oifname "${bridge}" iifname "${uplink}" ip daddr ${ip} ct state { established, related } accept
          oifname "${bridge}" drop
        }
        chain output {
          type filter hook output priority filter - 5; policy accept;
          oifname "${bridge}" ip daddr ${ip} tcp dport 22 accept
          oifname "${bridge}" drop
        }
        chain nat {
          type nat hook postrouting priority srcnat; policy accept;
          oifname "${uplink}" ip saddr ${ip} masquerade
        }
      '';
  };

  systemd.tmpfiles.rules = [ "d ${runtime} 0755 root root -" ];
  systemd.services.agent-vm-storage = {
    description = "Provision dedicated quota-limited VM storage";
    after = [
      "zfs-import.target"
      "zfs-mount.service"
    ];
    requires = [ "zfs-import.target" ];
    path = [
      config.boot.zfs.package
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = # sh
      ''
        if ! zfs list -H -o name ${dataset} >/dev/null 2>&1; then
          zfs create -o mountpoint=${storage} -o quota=36G ${dataset}
        fi
        test "$(zfs get -Hp -o value quota ${dataset})" = 38654705664
        test "$(findmnt --mountpoint ${storage} -n -o SOURCE)" = ${dataset}
        # Tune just the disposable qcow2 filesystem. In particular, do not
        # inherit dedup from the SSD pool or cache guest data twice.
        zfs set recordsize=16K compression=lz4 atime=off primarycache=metadata \
          dedup=off sync=standard com.sun:auto-snapshot=false ${dataset}
        chown root:root ${storage}
        chmod 0711 ${storage}
      '';
  };

  systemd.sockets.agent-vm = {
    description = "Agent VM control socket";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "${runtime}/control.sock";
      SocketUser = "container-5021";
      SocketMode = "0600";
    };
  };
  systemd.services.agent-vm = {
    description = "Agent VM lease and SSH broker";
    requires = [
      "agent-vm-storage.service"
      "libvirtd.service"
    ];
    bindsTo = [ "nftables.service" ];
    after = [
      "agent-vm-storage.service"
      "libvirtd.service"
      "nftables.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      libvirt
      xorriso
      openssh
      coreutils
      systemd
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe app} serve ${args}";
      ExecStopPost = "${lib.getExe app} cleanup ${args}";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStopSec = 60;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ storage ];
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
      ];
      NoNewPrivileges = true;
    };
  };
  systemd.services.nerdctl-t3code = {
    wants = [ "agent-vm.socket" ];
    after = [ "agent-vm.socket" ];
  };

  system.build.agentVMImage = image;
}
