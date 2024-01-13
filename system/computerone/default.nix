{
  pkgs,
  user,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../bluetooth.nix
    ../nvidia.nix
    ../virtualization.nix
  ];

  networking.hostName = "computerone";
}
