{
  lib,
  pkgs,
  config,
  ...
}:
let
  # https://github.com/tale/headplane/blob/main/docs/Integrated-Mode.md

  baseDir = "/mnt/SSD/apps/headscale";
  headscaleVersion = "0.26.1"; # https://github.com/juanfont/headscale/releases/latest
  headplaneVersion = "0.6.0"; # https://github.com/tale/headplane/releases/latest
in
{
  sops.secrets.tailscaleEnv = { };

  virtualisation.oci-containers.containers = {
    headplane = {
      autoStart = true;
      user = "5000:5000";

      image = "ghcr.io/tale/headplane:${headplaneVersion}";
      volumes = [
        # https://github.com/tale/headplane/blob/main/docs/Configuration.md
        "${baseDir}/gui-config/config.yaml:/etc/headplane/config.yaml"

        # This should match headscale.config_path in your config.yaml
        "${baseDir}/config/config.yaml:/etc/headscale/config.yaml"

        # If using dns.extra_records in Headscale (recommended), this should
        # match the headscale.dns_records_path in your config.yaml
        "${baseDir}/config/dns_records.json:/etc/headscale/dns_records.json"

        # Headplane stores its data in this directory
        "${baseDir}/gui-data:/var/lib/headplane"

        # This is not docker but it should work nonetheless
        "/var/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];
      extraOptions = [
        "--ip=10.0.1.5"
      ];
      dependsOn = [
        "headscale"
      ];
    };

    headscale = {
      autoStart = true;
      user = "5000:5000";

      image = "headscale/headscale:${headscaleVersion}";
      cmd = [ "serve" ];
      labels = {
        "me.tale.headplane.target" = "headscale";
      };
      volumes = [
        "${baseDir}/data:/var/lib/headscale"
        "${baseDir}/run:/var/run/headscale"
        "${baseDir}/config:/etc/headscale"
      ];
      extraOptions = [
        "--ip=10.0.1.4"
      ];

      ports = [ "8080:8080" ];
    };

    tailscale = {
      autoStart = true;
      user = "5000:5000";

      image = "tailscale/tailscale:latest";
      environment = {
        TS_EXTRA_ARGS = "--advertise-routes=10.0.1.0/24 --login-server http://10.0.1.4:8080";
        TS_STATE_DIR = "/var/lib/tailscale";
        TS_USERSPACE = "false";
      };
      environmentFiles = [ config.sops.secrets.tailscaleEnv.path ];

      volumes = [
        "/dev/net/tun:/dev/net/tun"
        "${baseDir}/tailscale-data:/var/lib/tailscale"
      ];

      capabilities = {
        NET_ADMIN = true;
      };

      dependsOn = [
        "headscale"
      ];

      extraOptions = [
        "--ip=10.0.1.6"
      ];
    };
  };

  systemd.services = {
    podman-headscale.postStart =
      let
        setfacl = "${pkgs.acl}/bin/setfacl";
      in
      # sh
      ''
        sleep 5

        f="/mnt/SSD/apps/headscale"
        chown -R containers:containers $f
        ${setfacl} -R -m g:admin:rwx $f
        echo "Set permissions for $f"
      '';
  };

  # https://wiki.nixos.org/wiki/Tailscale#Optimize_the_performance_of_subnet_routers_and_exit_nodes
  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = [ "routable" ];
      script = # sh
        ''
          ${lib.getExe pkgs.ethtool} -K enp2s0 rx-udp-gro-forwarding on rx-gro-list off
        '';
    };
  };
}
