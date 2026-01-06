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
    ../../../containers/bind9

    ../../../containers/radarr.nix
    ../../../containers/jackett.nix
    ../../../containers/sonarr.nix
    ../../../containers/flaresolverr.nix

    ../../../containers/jellyfin.nix

    ../../../containers/stirling-pdf.nix
    ../../../containers/opencloud.nix

    ../../../containers/mc-runner
  ];

  virtualisation = {
    podman = {
      enable = true;

      autoPrune = {
        enable = true;
        dates = "weekly";
      };

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
