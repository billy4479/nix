{
  pkgs,
  user,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../bluetooth.nix
    ../nvidia.nix
  ];

  networking.hostName = "computerone";
}
