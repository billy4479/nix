{ pkgs, serverone }:
let
  container = serverone.nerdctl-containers.certbot;
  certbot = pkgs.certbot.withPlugins (plugins: [ plugins.certbot-dns-cloudflare ]);
in
assert container.imageToBuild.image == "certbot:nix-local";
pkgs.runCommand "certbot-cloudflare-test" { } # sh
  ''
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
