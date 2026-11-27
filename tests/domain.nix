{ pkgs, mkHosts }:
let
  domain = "example.test";
  hosts = mkHosts domain;
  server = hosts.nixosConfigurations.serverone.config;
  vps = hosts.nixosConfigurations.vps-proxy.config;
  home = hosts.homeConfigurations."billy@portatilo".config;
  services = server.polpetta.services;
  mount =
    service: path:
    pkgs.lib.findFirst (
      v: v.containerPath == path
    ) (throw "Missing ${service}:${path}") services.${service}.container.volumes;
  volume = service: path: (mount service path).hostPath;
  policyPath = "/etc/headscale/policy.hujson";
  inherit (server.polpetta.generated) adminDnsRecords adminIngress legacyAdminDnsRecords;
  bind = volume "bind9" "/etc/bind";
  adminAddress = adminIngress.address;
  newAdminUis = [
    "agent-up"
    "grafana"
    "headplane"
    "jackett"
    "mircrewrr"
    "qbittorrent"
    "radarr"
    "sonarr"
    "syncthing"
    "t3code"
  ];
  tailnetUis = [
    "bentopdf"
    "ff"
    "immich"
    "outline"
    "searxng"
    "seerr"
    "radicale"
  ];
  nginx = pkgs.callPackage ../containers/nginx/package.nix {
    inherit domain;
    inherit (server.polpetta) externalTrafficFrom;
    inherit (server.polpetta.generated) nginxVhostsFile;
  };
in
assert services.opencloud.container.environment.OC_URL == "https://opencloud.${domain}";
assert services.opencloud.container.environment.OC_OIDC_ISSUER == "https://idp.${domain}";
assert pkgs.lib.last services.tsidp.container.cmd == "https://idp.${domain}";
assert services.radicale.container.environment.OIDC_ISSUER == "https://idp.${domain}";
assert services.grafana.container.environment.GF_SERVER_ROOT_URL == "https://grafana.${domain}";
assert vps.systemd.services.public-health-monitor.environment.PROBE_HOST == "headscale.${domain}";
assert home.programs.ssh.settings.serverone.data.HostName == "internal.${domain}";
assert (mount "headscale" policyPath).readOnly;
assert mount "headscale" policyPath == mount "headplane" policyPath;
pkgs.runCommand "domain-test"
  {
    passAsFile = [ "adminDns" ];
    adminDns = adminDnsRecords;
    nativeBuildInputs = [ pkgs.bind ];
    legacyDns = pkgs.writeText "legacy-admin-dns.zone" legacyAdminDnsRecords;
  } # sh
  ''
    grep -F 'server_name ${domain};' ${nginx}/nginx.conf
    vhost() {
      awk -v name="$1" '
        /^server \{/ { block=""; matched=0 }
        { block=block $0 "\n" }
        $1 == "server_name" && $2 == name ";" { matched=1 }
        /^}/ && matched { printf "%s", block; exit }
      ' ${nginx}/vhosts.conf
    }
    for name in ${builtins.toString newAdminUis}; do
      grep -Fx "$name.${domain}. IN A ${adminAddress}" "$adminDnsPath"
      grep -Fx "$name.internal.${domain}. IN A ${adminAddress}" "$legacyDns"
      for host in "$name.${domain}" "$name.internal.${domain}"; do
        vhost "$host" | grep -F 'listen ${toString adminIngress.port} ssl;'
        if vhost "$host" | grep -E 'listen (443|4443) '; then exit 1; fi
      done
    done
    for name in ${builtins.toString tailnetUis}; do
      for host in "$name.${domain}" "$name.internal.${domain}"; do
        vhost "$host" | grep -F 'allow 100.64.0.0/10;'
        vhost "$host" | grep -F 'deny all;'
        if vhost "$host" | grep -E 'allow (10\.0\.0\.0/8|192\.168\.0\.0/16);'; then exit 1; fi
      done
    done
    vhost 'jellyfin.${domain}' | grep -F 'allow 192.168.0.0/16;'
    vhost 'idp.${domain}' | grep -F 'allow 100.64.0.0/10;'
    test -z "$(vhost 'idp.internal.${domain}')"
    vhost 'ff.internal.${domain}' | grep -F 'try_files "" @canonical;'
    vhost 'ff.internal.${domain}' | grep -F 'return 307 https://ff.${domain}$request_uri;'
    vhost 'opencloud.${domain}' | grep -F 'listen 4443 ssl proxy_protocol;'
    if vhost 'opencloud.${domain}' | grep -F 'deny all;'; then exit 1; fi
    grep -F 'server_url: https://headscale.${domain}:443' ${volume "headscale" "/etc/headscale/config.yaml"}
    grep -F 'mode: file' ${volume "headscale" "/etc/headscale/config.yaml"}
    grep -F 'path: ${policyPath}' ${volume "headscale" "/etc/headscale/config.yaml"}
    ${pkgs.jq}/bin/jq -e --arg route '${adminAddress}/32' \
      '.autoApprovers.routes[$route] == ["tag:serverone"]' ${volume "headscale" policyPath}
    grep -F 'hostname: derp.${domain}' ${volume "headscale" "/etc/headscale/derp-custom.yaml"}
    grep -F 'issuer: "https://idp.${domain}"' ${volume "headplane" "/etc/headplane/config.yaml"}
    grep -F 'base_url: "https://searxng.${domain}/"' ${volume "searxng" "/etc/searxng/settings.yml"}
    grep -F 'zone "${domain}"' ${bind}/named.conf
    grep -F 'www        IN CNAME ${domain}.' ${bind}/wg-public.zone
    for view in lan wg; do
      for zone in public internal; do
        origin=${domain}
        if [ "$zone" = internal ]; then origin=internal.$origin; fi
        sed 's|/etc/bind/|${bind}/|g' "${bind}/$view-$zone.zone" > zonefile
        named-checkzone -D "$origin" zonefile > "$view-$zone.canonical"
      done
    done
    grep -E '^grafana\.${domain}\.\s+60\s+IN\s+A\s+10\.0\.2\.6$' wg-public.canonical
    grep -E '^mc\.${domain}\.\s+60\s+IN\s+A\s+' wg-public.canonical
    if grep -Fq '10.0.2.6' lan-public.canonical; then exit 1; fi
    touch "$out"
  ''
