{ config, ... }:
{
  sops.secrets.tailscale-key = { };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets.tailscale-key.path;
    useRoutingFeatures = "client";
    extraSetFlags = [
      "--accept-routes"
    ];
    extraUpFlags = [
      "--login-server"
      "https://headscale.polpetta.online"
    ];
  };
}
