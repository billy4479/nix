{
  pkgs,
  domain,
  lib,
  flakeInputs,
  ...
}:
let
  name = "derper-derp";
  hostname = "derp.${domain}";
  # Loopback only: clients reach the relay through the SNI demuxer on :443
  # (sni-demux.nix), the port itself stays firewall-closed.
  port = 8443;
  uploadUser = "derp-cert-sync";
  certStagingDir = "/var/lib/${uploadUser}";
  certDir = "/var/lib/derp-certificates";
  tools = pkgs.callPackage ../../../services/derp-certificates { };
  validationArgs = "--staging-dir ${certStagingDir} --hostname ${hostname} --ca-file ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
in
{
  users.users.${name} = {
    isSystemUser = true;
    group = name;
  };
  users.groups.${name} = { };

  users.users.${uploadUser} = {
    isSystemUser = true;
    group = uploadUser;
    home = certStagingDir;
    shell = pkgs.bash;
    # SSH requires an executable shell even for a forced command. No shell,
    # forwarding, SFTP, or arbitrary command is authorized by this key.
    openssh.authorizedKeys.keys = [
      ''restrict,command="${tools}/bin/derp-certificates receive ${validationArgs}" ${lib.removeSuffix "\n" (builtins.readFile "${flakeInputs.secrets-repo}/public_keys/ssh/serverone_certsync.pub")}''
    ];
  };
  users.groups.${uploadUser} = { };

  systemd.tmpfiles.rules = [
    "d ${certStagingDir} 0700 ${uploadUser} ${uploadUser} -"
    "d ${certDir} 0750 root ${name} -"
  ];

  # Installs pushed certs into the relay's state dir and restarts it. Runs at
  # boot (so the relay finds its cert before starting) and whenever serverone
  # drops a renewed cert in the staging dir.
  systemd.services."${name}-cert-sync" = {
    description = "Install DERP relay TLS certs pushed from serverone";
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "60s";
      UMask = "0077";
      ExecStart = "${tools}/bin/derp-certificates install ${validationArgs} --install-dir ${certDir} --group ${name}";
    };
  };

  systemd.paths."${name}-cert-sync" = {
    description = "Watch for DERP relay TLS certs pushed from serverone";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "${certStagingDir}/bundle.json";
      Unit = "${name}-cert-sync.service";
    };
  };

  # Reconcile an unchanged upload too: a transient install failure must not
  # remain stuck merely because subsequent uploads contain the same bundle.
  systemd.timers."${name}-cert-sync" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
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
      ExecStart = "${pkgs.derper}/bin/derper -derp=true -stun=false -a 127.0.0.1:${toString port} -http-port -1 -certmode=manual -certdir ${certDir}/current -hostname ${hostname} -verify-client-url=https://headscale.${domain}/verify -c /var/lib/${name}/derper.conf";

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
