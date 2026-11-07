{
  pkgs,
  domain,
  lib,
  config,
  ...
}:
let
  name = "certbot";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  id = 132;
  derpHostname = "derp.${domain}";
  certificateTools = pkgs.callPackage ../services/derp-certificates { };
in
{
  sops.secrets.cloudflare-dns-token = {
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = config.users.users.containers.group;
    restartUnits = [ "nerdctl-certbot.service" ];
  };

  # Accepted only by the dedicated forced-command upload account on the VPS.
  sops.secrets.derp-cert-sync-ssh-key = { };

  systemd = {
    timers."certbot-renew" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnCalendar = "*-*-* 00,12:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
        Unit = "certbot-renew.service";
      };
    };
    services."certbot-renew" = {
      path = [ pkgs.openssh ];
      script = # sh
        ''
          # Unit ordering does not imply that nerdctl has finished creating the
          # container. Wait for actual exec readiness, with a bounded retry.
          for attempt in $(seq 1 60); do
            if ${lib.getExe pkgs.nerdctl} exec certbot certbot --version >/dev/null 2>&1; then
              break
            fi
            if [ "$attempt" = 60 ]; then
              echo "certbot container did not become ready" >&2
              exit 1
            fi
            sleep 2
          done

          # A separate lineage prevents the public VPS from holding the web
          # wildcard key. Existing lineages and their keys are left untouched.
          ${lib.getExe pkgs.nerdctl} exec certbot certbot certonly \
            --non-interactive --agree-tos --register-unsafely-without-email \
            --keep-until-expiring --cert-name ${derpHostname} -d ${derpHostname} \
            --dns-cloudflare-propagation-seconds 60 \
            --dns-cloudflare --dns-cloudflare-credentials /cloudflare.ini

          ${lib.getExe pkgs.nerdctl} exec certbot certbot -v renew \
            --dns-cloudflare-propagation-seconds 60 \
            --dns-cloudflare \
            --dns-cloudflare-credentials /cloudflare.ini

          ${lib.getExe pkgs.nerdctl} exec nginx nginx -s reload

          # Push one bounded bundle over the pinned SSH connection. The receiver
          # compares certificate AND key, validates them, and publishes atomically.
          key=${config.sops.secrets.derp-cert-sync-ssh-key.path}
          live=${baseSSDDir}/config/live/${derpHostname}
          ${certificateTools}/bin/derp-certificates send "$live/fullchain.pem" "$live/privkey.pem" |
            ssh -T -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
              -o StrictHostKeyChecking=yes -o ConnectTimeout=15 \
              derp-cert-sync@external.${domain}

          # Consumed by the node-exporter textfile collector, never a secret.
          install -d -m 0755 /var/lib/prometheus-node-exporter
          printf 'certbot_renew_last_success_seconds %s\n' "$(date +%s)" \
            >/var/lib/prometheus-node-exporter/.certbot.prom.tmp
          chmod 0644 /var/lib/prometheus-node-exporter/.certbot.prom.tmp
          mv /var/lib/prometheus-node-exporter/.certbot.prom.tmp \
            /var/lib/prometheus-node-exporter/certbot.prom
        '';
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "30min";
        User = "root";
      };

      requires = [
        "nerdctl-certbot.service"
        "nerdctl-nginx.service"
      ];
      after = [
        "nerdctl-certbot.service"
        "nerdctl-nginx.service"
      ];
    };
  };

  nerdctl-containers.${name} = {
    inherit id;
    imageToPull = "docker.io/certbot/dns-cloudflare";

    volumes = [
      {
        hostPath = "${baseSSDDir}/config";
        containerPath = "/etc/letsencrypt";
      }
      {
        hostPath = "${baseSSDDir}/logs";
        containerPath = "/var/log/letsencrypt";
      }
      {
        hostPath = "${baseSSDDir}/work";
        containerPath = "/var/lib/letsencrypt";
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
