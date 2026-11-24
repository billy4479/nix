{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "26.05";
  networking = {
    hostName = "agent-dev";
    useDHCP = false;
    usePredictableInterfaceNames = false;
    enableIPv6 = false;
    interfaces.eth0.ipv4.addresses = [
      {
        address = "10.231.87.2";
        prefixLength = 30;
      }
    ];
    defaultGateway = "10.231.87.1";
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };
  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/vda";
    };
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "ahci"
      "sr_mod"
      "isofs"
    ];
  };
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/run/agent-vm-seed" = {
    device = "/dev/disk/by-label/AGENTVM_SEED";
    fsType = "iso9660";
    options = [
      "ro"
      "nodev"
      "nosuid"
      "noexec"
      "nofail"
      "x-systemd.device-timeout=15s"
    ];
  };
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh = {
    enable = true;
    hostKeys = [ ];
    authorizedKeysFiles = lib.mkForce [ "/run/agent-vm/authorized_keys" ];
    settings = {
      HostKey = "/run/agent-vm/host_key";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "agent" ];
      DisableForwarding = true;
    };
  };
  systemd.services.sshd = {
    unitConfig.RequiresMountsFor = "/run/agent-vm-seed";
    serviceConfig.RuntimeDirectory = "agent-vm";
    preStart = # sh
      ''
        install -m 0600 /run/agent-vm-seed/host_key /run/agent-vm/host_key
        install -m 0644 /run/agent-vm-seed/authorized_keys /run/agent-vm/authorized_keys
      '';
  };
  environment.systemPackages = with pkgs; [
    git
    curl
    jq
    gcc
    gnumake
    python3
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  documentation.enable = false;

  system.build.agentVMImage = import (modulesPath + "/../lib/make-disk-image.nix") {
    inherit config lib pkgs;
    name = "agent-vm-base-image";
    diskSize = 32768;
    format = "qcow2-compressed";
  };
}
