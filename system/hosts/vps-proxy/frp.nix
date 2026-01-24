{ config, pkgs, ... }:
let
  name = "frp";
in
{
  networking.firewall = {
    allowedTCPPorts = [
      80
      443
      25565
      2333
    ];
    allowedUDPPorts = [
      19132
    ];
  };

  sops.secrets."frp-token" = { };

  sops.templates."frps.toml" = {

    content = # toml
      ''
        bindAddr = "0.0.0.0"
        bindPort = 2333

        auth.method = "token"
        auth.token = "${config.sops.placeholder."frp-token"}"

        allowPorts = [
          { start = 80, end = 80 },
          { start = 443, end = 443 },
          { start = 25565, end = 25565 },
          { start = 19132, end = 19132 }
        ]
      '';
  };

  systemd.services.${name} = {
    description = "FRP Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig =
      let
        runtimeDir = "/run/${name}";
      in
      {
        ExecStartPre =
          "+"
          + (pkgs.writeShellScript "frp-prestart" ''
            DYNUSER_UID=$(stat -c %u ${runtimeDir})
            DYNUSER_GID=$(stat -c %g ${runtimeDir})
            echo "$DYNUSER_UID:$DYNUSER_UID"
            install -m 600 -o $DYNUSER_UID -g $DYNUSER_GID \
              ${config.sops.templates."frps.toml".path} ${runtimeDir}/frps.toml
          '');
        ExecStart = "${pkgs.frp}/bin/frps --strict_config -c ${runtimeDir}/frps.toml";

        # Taken from https://github.com/NixOS/nixpkgs/blob/ed142ab1b3a092c4d149245d0c4126a5d7ea00b0/nixos/modules/services/networking/frp.nix
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 15;
        DynamicUser = true;
        LimitNOFILE = "1048576";
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0700";
        # Hardening
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
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
        StateDirectory = name;
        StateDirectoryMode = "0700";
        UMask = "0007";
      };
  };
}
