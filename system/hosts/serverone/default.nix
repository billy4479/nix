{ flakeInputs, ... }:
{
  imports = [
    ../../modules/power-management
    ../../modules/graphics/intel.nix
    ./hardware-configuration.nix
    flakeInputs.disko.nixosModules.disko
    ./disko.nix
  ];

  # https://github.com/nix-community/disko/issues/581#issuecomment-2260602290
  boot.zfs.extraPools = [
    "hdd_pool"
    "ssd_pool"
  ];

  services.openssh = {
    enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImNlhEzdTtpz598zDIQBnh39tLbXi1bZgkMY1qBQ/PS giachi.ellero@gmail.com"
  ];

  networking = {
    hostId = "d3cb129c";
    hostName = "serverone";
  };

}
