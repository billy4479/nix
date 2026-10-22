{ pkgs, ... }:
let
  name = "derper-stun";
in
{
  systemd.services.${name} = {
    description = "STUN-only server (derper)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      # `-a :8090` must stay on all interfaces: STUN inherits the same bind IP,
      # and binding it to a single address would break the UDP listener.
      # The HTTP listener is unused (not open in the firewall), it only needs
      # to be disabled for TLS (`-http-port -1`).
      ExecStart = "${pkgs.derper}/bin/derper -derp=false -stun=true -stun-port 3478 -a :8090 -http-port -1 -c /var/lib/derper/derper.conf";

      Type = "simple";
      Restart = "on-failure";
      RestartSec = 15;
      DynamicUser = true;
      StateDirectory = "derper";
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
