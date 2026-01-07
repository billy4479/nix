{
  flakeInputs,
  pkgs,
  ...
}:
{
  imports = [
    ../../../containers/syncthing.nix
    ../../../containers/immich
    ../../../containers/qbittorrent.nix

    ../../../containers/calendar-proxy.nix

    ../../../containers/cloudflared.nix
    ../../../containers/certbot.nix
    ../../../containers/nginx
    ../../../containers/bind9

    # ../../../containers/radarr.nix
    # ../../../containers/jackett.nix
    # ../../../containers/sonarr.nix
    # ../../../containers/flaresolverr.nix

    ../../../containers/jellyfin.nix

    # ../../../containers/stirling-pdf.nix
    ../../../containers/opencloud.nix

    ../../../containers/mc-runner
  ];

  nixpkgs.overlays = [ flakeInputs.nix-snapshotter.overlays.default ];

  environment.systemPackages = [
    pkgs.nerdctl
    pkgs.cni-plugins
  ];

  services.nix-snapshotter = {
    enable = true;
    setSocketVariable = true;
  };

  virtualisation = {
    containerd = {
      enable = true;
      nixSnapshotterIntegration = true;
    };

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

  environment.etc = {
    "nerdctl/nerdctl.toml".text = ''
      cni_path = "${pkgs.cni-plugins}/bin"
      cni_netconfpath = "/etc/cni/net.d"
    '';

    "cni/net.d/10-nerdctl.conflist".text = builtins.toJSON {
      cniVersion = "1.0.0";
      name = "nerdctl-bridge";
      plugins = [
        {
          type = "bridge";
          bridge = "nerdctl0";
          isGateway = true;
          ipMasq = true;
          hairpinMode = true;
          ipam = {
            type = "host-local";
            routes = [ { dst = "0.0.0.0/0"; } ];
            ranges = [
              [
                {
                  subnet = "10.0.2.0/24";
                  gateway = "10.0.2.1";
                }
              ]
            ];
          };
        }
        {
          type = "portmap";
          capabilities = {
            portMappings = true;
          };
        }
        { type = "firewall"; }
        { type = "tuning"; }
      ];
    };
  };
}
