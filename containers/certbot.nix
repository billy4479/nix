{
  pkgs,
  lib,
  config,
  ...
}:
let
  name = "certbot";
  baseSSDDir = "/mnt/SSD/apps/${name}";
in
{
  sops.secrets.cloudflare-dns-token = {
    owner = config.users.users.containers.name;
    group = config.users.users.containers.group;
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
          ${lib.getExe pkgs.nerdctl} exec certbot certbot renew \
            --dns-cloudflare-propagation-seconds 60 \
            --dns-cloudflare \
            --dns-cloudflare-credentials /cloudflare.ini

          ${lib.getExe pkgs.nerdctl} exec nginx nginx -s reload
        '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
    };
  };

  nerdctl-containers.${name} = {
    id = 132;
    imageToPull = "docker.io/certbot/dns-cloudflare";

    volumes = [
      {
        hostPath = baseSSDDir;
        containerPath = "/etc/letsencrypt";
      }
      {
        hostPath = "${baseSSDDir}/logs";
        containerPath = "/var/log/letsencrypt";
      }
      {
        hostPath = config.sops.secrets.cloudflare-dns-token.path;
        containerPath = "/cloudflare.ini";
        readOnly = true;
      }
    ];

    entrypoint = "/bin/sh";
    cmd = [
      "-c"
      "trap : TERM INT; sleep infinity & wait"
    ];
  };
}
