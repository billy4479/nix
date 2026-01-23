{ config, pkgs, ... }:
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

  sops.secrets."gost-credentials/username" = { };
  sops.secrets."gost-credentials/password" = { };

  sops.templates."gost.yaml" = {
    content = # yaml
      ''
        services:
        - name: service-relay
          addr: :2333
          handler:
            type: relay
            metadata:
                proxyProtocol: 1
            auth:
              username: "${config.sops.placeholder."gost-credentials/username"}"
              password: "${config.sops.placeholder."gost-credentials/password"}"
          listener:
            type: tcp 
      '';
  };

  systemd.services.gost = {
    description = "GOST Tunnel Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStartPre =
        "+"
        + (pkgs.writeShellScript "gost-prestart" ''
          DYNUSER_UID=$(stat -c %u /run/gost)
          DYNUSER_GID=$(stat -c %g /run/gost)
          echo "$DYNUSER_UID:$DYNUSER_UID"
          install -m 600 -o $DYNUSER_UID -g $DYNUSER_GID \
            ${config.sops.templates."gost.yaml".path} /run/gost/gost.yaml
        '');
      ExecStart = "${pkgs.gost}/bin/gost -C /run/gost/gost.yaml";

      # Taken from https://github.com/NixOS/nixpkgs/blob/ed142ab1b3a092c4d149245d0c4126a5d7ea00b0/nixos/modules/services/networking/rathole.nix
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
      DynamicUser = true;
      LimitNOFILE = "1048576";
      RuntimeDirectory = "gost";
      RuntimeDirectoryMode = "0700";
      # Hardening
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateDevices = true;
      PrivateMounts = true;
      PrivateTmp = true;
      # PrivateUsers=true breaks AmbientCapabilities=CAP_NET_BIND_SERVICE
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RemoveIPC = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      UMask = "0066";
    };
  };
}
