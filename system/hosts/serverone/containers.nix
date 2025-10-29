{ ... }:
{
  imports = [
    ../../../containers/syncthing.nix
    ../../../containers/immich.nix
    ../../../containers/qbittorrent.nix

    ../../../containers/calendar-proxy.nix

    ../../../containers/cloudflared.nix
    ../../../containers/certbot.nix
    ../../../containers/nginx
    ../../../containers/pihole.nix

    ../../../containers/radarr.nix
    ../../../containers/jackett.nix
    ../../../containers/sonarr.nix
    ../../../containers/flaresolverr.nix

    ../../../containers/jellyfin.nix
  ];

  virtualisation = {
    podman = {
      enable = true;

      defaultNetwork.settings = {
        dns_enabled = false;
        subnets = [
          {
            gateway = "10.0.1.1";
            subnet = "10.0.1.0/24";
          }
        ];
      };
    };
    oci-containers.backend = "podman";
  };
}
