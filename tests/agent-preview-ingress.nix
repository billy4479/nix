{
  pkgs,
  serverone,
  domain,
}:
let
  server =
    (serverone.extendModules {
      modules = [ { polpetta.agentPreview.enable = true; } ];
    }).config;
  inherit (server.polpetta.generated) adminIngress agentPreview nginxVhostsFile;
  volume =
    service: path:
    (pkgs.lib.findFirst (
      v: v.containerPath == path
    ) (throw "Missing ${service}:${path}") server.polpetta.services.${service}.container.volumes)
    .hostPath;
  nginx = pkgs.callPackage ../containers/nginx/package.nix {
    inherit domain nginxVhostsFile;
    inherit (server.polpetta) externalTrafficFrom;
  };
in
pkgs.runCommand "agent-preview-ingress-test" { nativeBuildInputs = [ pkgs.jq ]; } # sh
  ''
    records=${volume "bind9" "/etc/bind"}/admin-records.zone
    grep -Fx '${agentPreview.hostname}. IN A ${adminIngress.address}' "$records"
    grep -Fx '*.${agentPreview.hostname}. IN A ${adminIngress.address}' "$records"
    awk -v name='*.${agentPreview.hostname};' '
      /^server \{/ { block=""; matched=0 }
      { block=block $0 "\n" }
      $1 == "server_name" && $2 == name { matched=1 }
      /^}/ && matched { printf "%s", block; exit }
    ' ${nginx}/vhosts.conf > vhost
    test "$(grep 'listen' vhost | xargs)" = 'listen ${toString adminIngress.port} ssl;'
    grep -F 'deny all;' vhost
    jq -e --arg dest '${adminIngress.address}:${agentPreview.rawRange}' '
      [.acls[] | select(.dst | index($dest)) | [.src, .proto]] | sort
      == [[ ["group:admin"], "tcp" ], [ ["group:admin"], "udp" ]]
    ' ${volume "headscale" "/etc/headscale/policy.hujson"}
    touch "$out"
  ''
