{
  pkgs,
  lib,
  config,
  ...
}:
let
  name = "certbot";
  baseSSDDir = "/mnt/SSD/apps/${name}";
  id = 132;
in
{
  sops.secrets.cloudflare-dns-token = {
    owner = "container-${toString config.nerdctl-containers.${name}.uid}";
    group = config.users.users.containers.group;
  };

  # Key accepted by vps-proxy for billy, used to push the wildcard cert over
  # for the DERP relay (see system/hosts/vps-proxy/derper-derp.nix).
  sops.secrets.derp-cert-sync-ssh-key = { };

  systemd = {
    timers."certbot-renew" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = "12h";
        RandomizedDelaySec = "1h";
        Persistent = true;
        Unit = "certbot-renew.service";
      };
    };
    services."certbot-renew" = {
      path = [ pkgs.openssh ];
      script = # sh
        ''
          sleep 60 # HACK: wait for certbot container to be up

          ${lib.getExe pkgs.nerdctl} exec certbot certbot -v renew \
            --dns-cloudflare-propagation-seconds 60 \
            --dns-cloudflare \
            --dns-cloudflare-credentials /cloudflare.ini

          ${lib.getExe pkgs.nerdctl} exec nginx nginx -s reload

          # Ship the (wildcard) cert to vps-proxy for the DERP relay, which
          # installs and activates it via a path unit. Only push on actual
          # change so the remote relay is not restarted needlessly. The gate
          # tracks the private key: certbot generates a fresh key on every
          # renewal, so a changed key == renewed cert.
          #
          # This runs as root, which has no ssh aliases: use the public name
          # external.polpetta.online (host key pinned in ../system/hosts/
          # serverone/ssh.nix, resolves to the vps from every DNS view).
          key=${config.sops.secrets.derp-cert-sync-ssh-key.path}
          dest=billy@external.polpetta.online
          live=${baseSSDDir}/config/live/polpetta.online
          opts=(-i "$key" -o IdentitiesOnly=yes)
          if ! ssh "''${opts[@]}" "$dest" \
              'cmp -s - derp-certs/derp.polpetta.online.key' \
              < "$live/privkey.pem"; then
            scp -q "''${opts[@]}" "$live/fullchain.pem" \
              "$dest:derp-certs/derp.polpetta.online.crt"
            scp -q "''${opts[@]}" "$live/privkey.pem" \
              "$dest:derp-certs/derp.polpetta.online.key"
          fi
        '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
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
