{
  pkgs,
  lib,
  config,
  ...
}:
let
  containerName = "certbot";
  baseSSDDir = "/mnt/SSD/apps/${containerName}";
  inherit (import ./utils.nix) givePermissions;
in
{
  sops.secrets.cloudflare-dns-token = {
    owner = config.users.users.containers.name;
    group = config.users.users.containers.group;
  };

  virtualisation.oci-containers.containers."${containerName}" = {
    image = "docker.io/certbot/dns-cloudflare:latest";
    user = "5000:5000";

    volumes = [
      "${baseSSDDir}:/etc/letsencrypt:rw"
      "${baseSSDDir}/logs:/var/log/letsencrypt:rw"
      "${config.sops.secrets.cloudflare-dns-token.path}:/cloudflare.ini:ro"
    ];

    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      "trap : TERM INT; sleep infinity & wait"
    ];

    labels = {
      "io.containers.autoupdate" = "registry";
    };

    extraOptions = [ "--ip=10.0.1.132" ];
  };

  systemd = {
    timers."certbot-renew" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitAcriveSec = "12h";
        RandomizedDelaySec = "1h";
        Persistent = true;
        Unit = "certbot-renew.service";
      };
    };
    services."certbot-renew" = {
      script = # sh
        ''
          ${lib.getExe pkgs.podman} exec certbot certbot renew \
            --dns-cloudflare-propagation-seconds 60 \
            --dns-cloudflare \
            --dns-cloudflare-credentials /cloudflare.ini

          ${lib.getExe pkgs.podman} exec nginx nginx -s reload
        '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
    };
  };
}
// (givePermissions {
  inherit pkgs containerName;
  adminOnlyDirs = [ baseSSDDir ];
})
