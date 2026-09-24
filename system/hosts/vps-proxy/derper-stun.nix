{ pkgs, ... }:
let
  name = "derper-stun";
in
{
  systemd.services.${name} = {
    description = "Tailscale STUN-only server (derper)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      # Order after frps so the old frps (which may still hold UDP 3478 from a
      # previously registered stun proxy) releases the port before we bind it.
      # derper discards a failed UDP listen silently, so losing the race here
      # would leave the service running without a STUN server.
      "frp.service"
    ];

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
