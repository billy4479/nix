{
  pkgs,
  ...
}:
let
  name = "derper-derp";
  hostname = "derp.polpetta.online";
  port = 8443;
  # serverone's certbot-renew pushes the (wildcard) polpetta.online cert here
  # via plain scp; the path unit below picks it up and activates the relay.
  certStagingDir = "/home/billy/derp-certs";
in
{
  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };
  users.groups.${name} = { };

  networking.firewall.allowedTCPPorts = [ port ];

  systemd.tmpfiles.rules = [
    "d ${certStagingDir} 0700 billy users -"
  ];

  # Installs pushed certs into the relay's state dir and restarts it. Runs at
  # boot (so the relay finds its cert before starting) and whenever serverone
  # drops a renewed cert in the staging dir.
  systemd.services."${name}-cert-sync" = {
    description = "Install DERP relay TLS certs pushed from serverone";
    path = [ pkgs.openssl ];
    serviceConfig = {
      Type = "oneshot";
    };
    # No-op (without failing) if the relay isn't running yet: at boot this
    # runs before derper-derp, its only job there is to place the certs.
    script = # sh
      ''
        crt=${certStagingDir}/${hostname}.crt
        key=${certStagingDir}/${hostname}.key
        if [ -s "$crt" ] && [ -s "$key" ]; then
          # The two files are pushed by separate scp runs, so refuse to
          # install a mismatched (e.g. partially pushed) pair: keep the
          # currently installed certs, which stay valid until renewal.
          if ! cmp -s \
            <(openssl x509 -in "$crt" -noout -pubkey) \
            <(openssl pkey -in "$key" -pubout); then
            echo "staged cert/key pair mismatch, skipping install" >&2
            exit 1
          fi
          install -d -o ${name} -g ${name} -m 0700 /var/lib/${name}
          install -o ${name} -g ${name} -m 0644 "$crt" /var/lib/${name}/
          install -o ${name} -g ${name} -m 0600 "$key" /var/lib/${name}/
          systemctl try-restart ${name}.service
        fi
      '';
  };

  systemd.paths."${name}-cert-sync" = {
    description = "Watch for DERP relay TLS certs pushed from serverone";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "${certStagingDir}/${hostname}.key";
      Unit = "${name}-cert-sync.service";
    };
  };

  systemd.services.${name} = {
    description = "Tailscale DERP relay server (derper)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "${name}-cert-sync.service"
    ];
    wants = [ "${name}-cert-sync.service" ];

    serviceConfig = {
      # derper needs a config file (-c): on first start it generates the DERP
      # server private key and writes {"PrivateKey": "privkey:..."} there.
      #
      # -verify-client-url makes headscale admit connections: derper POSTs the
      # client's node key to /verify and only relays for registered nodes.
      # Fail-open (the default) is deliberate: if headscale is unreachable the
      # relay stays up, only admission is unverified for that window.
      ExecStart = "${pkgs.derper}/bin/derper -derp=true -stun=false -a :${
        toString port
      } -http-port -1 -certmode=manual -certdir /var/lib/${name} -hostname ${hostname} -verify-client-url=https://headscale.polpetta.online/verify -c /var/lib/${name}/derper.conf";

      Type = "simple";
      Restart = "on-failure";
      RestartSec = 15;
      User = name;
      Group = name;
      StateDirectory = name;
      StateDirectoryMode = "0700";
      UMask = "0007";
      # Hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateDevices = true;
      ProtectHostname = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
    };
  };
}
