{ flakeInputs, ... }:
{
  imports = [
    ../../modules/power-management
    ../../modules/graphics/intel.nix
    # ./hardware-configuration.nix
    flakeInputs.disko.nixosModules.disko
    ./disko.nix
  ];

  services.openssh = {
    enable = true;
  };

  users.users.root.openssh.authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImNlhEzdTtpz598zDIQBnh39tLbXi1bZgkMY1qBQ/PS giachi.ellero@gmail.com"
  ];

  networking.hostId = "d3cb129c";
}
