{
  flakeInputs,
  pkgs,
  ...
}:
{
  imports = [
    ../../../containers/module.nix

    ../../../containers/headscale

    ../../../containers/syncthing.nix
    ../../../containers/immich
    ../../../containers/qbittorrent.nix

    ../../../containers/certbot.nix
    ../../../containers/nginx
    ../../../containers/bind9
    ../../../containers/frp.nix

    ../../../containers/radarr.nix
    ../../../containers/jackett.nix
    ../../../containers/sonarr.nix
    ../../../containers/flaresolverr.nix

    ../../../containers/jellyfin.nix

    ../../../containers/stirling-pdf.nix
    ../../../containers/opencloud.nix

    ../../../containers/mc-runner
    ../../../containers/calendar-proxy.nix
  ];

  nixpkgs.overlays = [ flakeInputs.nix-snapshotter.overlays.default ];

  environment.systemPackages = [
    pkgs.nerdctl
    pkgs.cni-plugins
  ];

  services.nix-snapshotter = {
    enable = true;
  };

  virtualisation.containerd = {
    enable = true;
    nixSnapshotterIntegration = true;
  };

  environment.etc = {
    "nerdctl/nerdctl.toml".text = # toml
      ''
        address = "unix:///run/containerd/containerd.sock"
        namespace = "default"
        snapshotter = "nix"

        cni_path = "${pkgs.cni-plugins}/bin"
        cni_netconfpath = "/etc/cni/net.d"
      '';

    "containerd/config.toml".text = # toml
      ''
        version = 2

        [proxy_plugins]
          [proxy_plugins.nix]
            type = "snapshot"
            address = "/run/nix-snapshotter/nix-snapshotter.sock"

        # Needed so image unpack/import uses nix-snapshotter for the target platform(s)
        [plugins."io.containerd.transfer.v1.local"]
          [[plugins."io.containerd.transfer.v1.local".unpack_config]]
            platform = "linux/amd64"
            snapshotter = "nix"

        # Optional (only relevant to CRI/Kubernetes; harmless if CRI is enabled but you don't use it)
        [plugins."io.containerd.grpc.v1.cri".containerd]
          snapshotter = "nix"
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
                  subnet = "10.0.1.0/24";
                  gateway = "10.0.1.1";
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
