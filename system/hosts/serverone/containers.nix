{
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
    ../../../containers/byparr.nix

    ../../../containers/jellyfin.nix

    ../../../containers/stirling-pdf.nix
    ../../../containers/opencloud.nix
    ../../../containers/searxng

    ../../../containers/mc-runner
    ../../../containers/calendar-proxy.nix
    ../../../containers/ff.nix
    ../../../containers/giuoco-del-divertimento.nix
  ];

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

  networking.firewall = {
    # serverone is a Tailscale subnet router for the nerdctl bridge. Packets
    # addressed to container IPs are forwarded, so allowedUDPPorts/allowedTCPPorts
    # do not apply; accept tailscale0 -> nerdctl0 and allow the replies back.
    # Loose reverse-path filtering is needed because Tailscale routes live in a
    # policy routing table and strict rpfilter can drop these packets before FORWARD.
    checkReversePath = "loose";
    extraCommands = # sh
      ''
        iptables -C FORWARD -i tailscale0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT 2>/dev/null ||
          iptables -I FORWARD 1 -i tailscale0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT
        iptables -C FORWARD -i nerdctl0 -o tailscale0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null ||
          iptables -I FORWARD 1 -i nerdctl0 -o tailscale0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      '';
    extraStopCommands = # sh
      ''
        iptables -D FORWARD -i tailscale0 -o nerdctl0 -d 10.0.1.0/24 -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i nerdctl0 -o tailscale0 -s 10.0.1.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      '';
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
