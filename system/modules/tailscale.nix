{ config, ... }:
{
  sops.secrets.tailscale-key = { };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets.tailscale-key.path;
    useRoutingFeatures = "client";
    extraUpFlags = [
      "--login-server"
      "https://headscale.polpetta.online"
    ];
  };
}
