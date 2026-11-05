{
  pkgs,
  serverone,
  vps,
}:
let
  inherit (pkgs) lib;
  # Check every sops file consumed at container startup, not just this incident's
  # examples, so future secret-backed mounts cannot silently omit restarts.
  rendered = lib.attrValues serverone.sops.templates ++ lib.attrValues serverone.sops.secrets;
  consumerChecks = lib.concatLists (
    lib.mapAttrsToList (
      name: container:
      let
        paths = container.environmentFiles ++ map (volume: volume.hostPath) container.volumes;
      in
      map (secret: {
        unit = "nerdctl-${name}.service";
        restarts = secret.restartUnits;
      }) (lib.filter (secret: lib.elem secret.path paths) rendered)
    ) serverone.nerdctl-containers
  );
  localExporters = map (name: serverone.services.prometheus.exporters.${name}) [
    "node"
    "smartctl"
    "zfs"
    "nginx"
    "blackbox"
  ];
in
assert lib.assertMsg (lib.all (
  consumer: lib.elem consumer.unit consumer.restarts
) consumerChecks) "Every container-consumed sops file must restart its consumer on rotation";
assert lib.assertMsg (lib.all
  (
    host:
    lib.all (
      interface:
      let
        unit = host.systemd.services."wireguard-${interface}".name;
      in
      lib.elem unit host.sops.secrets.wireguard-key.restartUnits
    ) (builtins.attrNames host.networking.wireguard.interfaces)
  )
  [
    serverone
    vps
  ]
) "Every wireguard interface must restart on key rotation";
assert serverone.systemd.timers.certbot-renew.timerConfig.OnCalendar == "*-*-* 00,12:00:00";
assert !(serverone.systemd.services.certbot-renew.serviceConfig.RemainAfterExit or false);
assert vps.systemd.services.derper-derp-cert-sync.serviceConfig.TimeoutStartSec == "60s";
assert vps.systemd.timers.derper-derp-cert-sync.timerConfig.OnCalendar == "hourly";
assert lib.all (
  key: lib.hasPrefix "restrict,command=" key
) vps.users.users.derp-cert-sync.openssh.authorizedKeys.keys;
assert serverone.nerdctl-containers.openchamber.privateNixStore.wipeAboveGib == null;
assert serverone.systemd.timers.openchamber-nix-gc.timerConfig.OnCalendar == "daily";
assert lib.hasSuffix (
  " exec openchamber /bin/nh clean user --elevation-strategy none --keep 5 --keep-since 7d --keep-one --max 107374182400"
) serverone.systemd.services.openchamber-nix-gc.serviceConfig.ExecStart;
assert lib.elem "polpetta-raw-firewall.service" serverone.systemd.services.containerd.requires;
assert serverone.systemd.services.polpetta-raw-firewall.reloadIfChanged;
assert vps.systemd.services.edge-forwarding.restartIfChanged;
assert !vps.systemd.services.edge-forwarding.reloadIfChanged;
assert lib.all (exporter: exporter.listenAddress == "127.0.0.1") localExporters;
assert serverone.services.prometheus.alertmanager.listenAddress == "127.0.0.1";
pkgs.runCommand "server-security-policy-test" { } # sh
  ''
    touch "$out"
  ''
