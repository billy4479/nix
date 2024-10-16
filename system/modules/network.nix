{ lib, ... }:
{
  networking = {
    networkmanager = {
      enable = true;
      dns = "none";
    };
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    # hosts = {
    #   "0.0.0.0" = [ "www.youtube.com" ];
    # };
  };
  services.resolved.enable = lib.mkForce false;
}
