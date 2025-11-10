{
  pkgs,
  lib,
  config,
  ...
}:
let
  name = "certbot";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  inherit ((import ./utils.nix) { inherit pkgs config; }) makeContainer;
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
// makeContainer {
  inherit name;
  image = "docker.io/certbot/dns-cloudflare";
  ip = "10.0.1.132";

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

  adminOnlyDirs = [ baseSSDDir ];
}
