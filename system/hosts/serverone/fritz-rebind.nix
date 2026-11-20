{
  config,
  domain,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.networking.fritzRebindSync;
  credential = config.sops.templates."fritz-rebind-credential".path;
  sync = lib.getExe (pkgs.callPackage ../../../packages/fritz-rebind-sync { });
  manifest = pkgs.writeText "fritz-rebind-names.json" (
    builtins.toJSON {
      address = "192.168.2.1";
      pin = "sha256//JT2qoEIbczSmIvStlCyRcG2Y59+oL2PDyPhe1dq7Jmc=";
      zone = domain;
      prune = true;
      names = lib.unique (
        [
          domain
          "www.${domain}"
          "internal.${domain}"
        ]
        ++ config.polpetta.generated.rebindNames
        ++ cfg.extraNames
      );
    }
  );
in
{
  options.networking.fritzRebindSync.extraNames = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Keep additional FRITZ!Box rebind exceptions within the deployment domain.";
  };

  config = {
    sops.secrets.fritz-admin-password = { };
    sops.templates."fritz-rebind-credential" = {
      mode = "0400";
      content = ''
        fritz6398
        ${config.sops.placeholder.fritz-admin-password}
      '';
    };

    environment.etc."fritz-rebind-sync/manifest.json".source = manifest;
    # Preserve the manually configured Stirling PDF exception, which is not a generated vhost.
    networking.fritzRebindSync.extraNames = [ "stirling-pdf.internal.${domain}" ];
    system.activationScripts.fritz-rebind-sync = lib.stringAfter [ "specialfs" ] (
      # sh
      ''
        # Queue the new unit, rather than using the previous generation's unit during activation.
        mkdir -p /run/nixos
        echo fritz-rebind-sync.service >>/run/nixos/activation-restart-list
      ''
    );

    systemd.services.fritz-rebind-sync = {
      description = "Synchronize FRITZ!Box DNS rebind exceptions";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExists = credential;
      serviceConfig = {
        Type = "oneshot";
        LoadCredential = "router:${credential}";
        ExecStart = "${sync} --apply ${manifest} %d/router";
        TimeoutStartSec = "90s";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
      };
    };
  };
}
