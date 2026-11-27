{ pkgs, serverone }:
let
  container = serverone.nerdctl-containers.certbot;
  certbot = pkgs.certbot.withPlugins (plugins: [ plugins.certbot-dns-cloudflare ]);
  hook = pkgs.lib.findFirst (
    volume: volume.containerPath == "/etc/letsencrypt/renewal-hooks/deploy/nginx-key-access"
  ) (throw "certbot nginx key deploy hook is missing") container.volumes;
  nginxUid = toString serverone.nerdctl-containers.nginx.uid;
  # Nix's build tmpfs can lack POSIX ACL support. Record the ACL command to
  # verify the hook's policy without depending on the builder's filesystem.
  aclRecorder = pkgs.writeShellScriptBin "setfacl" ''
    set -eu
    test "$1" = --set
    test "$2" = 'u::rw-,u:${nginxUid}:r--,g::---,m::r--,o::---'
    test -f "$3"
    printf '%s\n' "$3" >>"$ACL_LOG"
  '';
in
assert serverone.system.build.containerImages.certbot.image == "certbot:nix-local";
assert container.entrypoint == [ "/bin/sh" ];
assert hook.readOnly;
assert pkgs.lib.hasInfix "setfacl" serverone.systemd.services.nerdctl-nginx.preStart;
assert pkgs.lib.hasInfix
  (builtins.unsafeDiscardStringContext "exec nginx ${pkgs.lib.getExe pkgs.nginx} -s reload")
  serverone.systemd.services.certbot-renew.script;
pkgs.runCommand "certbot-cloudflare-test" { } # sh
  ''
    # Exercise the real hook with a recording setfacl, including live symlinks.
    sed 's|${pkgs.acl}/bin|${aclRecorder}/bin|g' ${hook.hostPath} >hook
    chmod +x hook
    export ACL_LOG="$PWD/acl.log"
    mkdir -p archive live
    for lineage in polpetta.online agent-preview.polpetta.online derp.polpetta.online; do
      mkdir -p "archive/$lineage" "live/$lineage"
      touch "archive/$lineage/privkey1.pem"
      chmod 0600 "archive/$lineage/privkey1.pem"
      ln -s "../../archive/$lineage/privkey1.pem" "live/$lineage/privkey.pem"
      RENEWED_LINEAGE="$PWD/live/$lineage" ./hook
      if [ "$lineage" = derp.polpetta.online ]; then
        ! grep -q "$lineage" "$ACL_LOG"
      else
        grep -Fx "$PWD/live/$lineage/privkey.pem" "$ACL_LOG"
      fi
    done
    test "$(wc -l <"$ACL_LOG")" = 2

    ${certbot}/bin/certbot plugins --authenticators \
      --config-dir "$TMPDIR/config" \
      --work-dir "$TMPDIR/work" \
      --logs-dir "$TMPDIR/logs" >plugins.txt
    grep -F '* dns-cloudflare' plugins.txt
    ${certbot}/bin/certbot --help dns-cloudflare >help.txt
    grep -F -- '--dns-cloudflare-credentials' help.txt
    grep -F -- '--dns-cloudflare-propagation-seconds' help.txt
    touch "$out"
  ''
