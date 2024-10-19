{ lib, config, ... }:
{
  sops.secrets.tailscale_key = { };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_key.path;
    openFirewall = true;
    useRoutingFeatures = lib.mkOverride 100 "client";
  };
}
