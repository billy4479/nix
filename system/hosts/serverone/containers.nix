{ ... }:
{
  imports = [
    ../../../containers/syncthing.nix
    ../../../containers/immich.nix
    ../../../containers/qbittorrent.nix
    ../../../containers/calendar-proxy.nix
    ../../../containers/cloudflared.nix
    ../../../containers/certbot.nix
  ];

  virtualisation = {
    podman = {
      enable = true;

      defaultNetwork.settings = {
        dns_enabled = true;
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
