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
  adminAddress = server.polpetta.generated.adminIngress.address;
  nginx = pkgs.callPackage ../containers/nginx/package.nix {
    inherit domain;
    inherit (server.polpetta) externalTrafficFrom;
    inherit (server.polpetta.generated) nginxVhostsFile;
  };
in
assert services.opencloud.container.environment.OC_URL == "https://opencloud.${domain}";
assert
  services.grafana.container.environment.GF_SERVER_ROOT_URL == "https://grafana.internal.${domain}";
assert vps.systemd.services.public-health-monitor.environment.PROBE_HOST == "headscale.${domain}";
assert home.programs.ssh.settings.serverone.data.HostName == "internal.${domain}";
assert (mount "headscale" policyPath).readOnly;
assert mount "headscale" policyPath == mount "headplane" policyPath;
pkgs.runCommand "domain-test" { } # sh
  ''
    grep -F 'server_name ${domain};' ${nginx}/nginx.conf
    grep -F 'server_name idp.internal.${domain};' ${nginx}/vhosts.conf
    grep -F 'server_url: https://headscale.${domain}:443' ${volume "headscale" "/etc/headscale/config.yaml"}
    grep -F 'mode: file' ${volume "headscale" "/etc/headscale/config.yaml"}
    grep -F 'path: ${policyPath}' ${volume "headscale" "/etc/headscale/config.yaml"}
    grep -F '"${adminAddress}/32": ["tag:serverone"]' ${volume "headscale" policyPath}
    grep -F 'hostname: derp.${domain}' ${volume "headscale" "/etc/headscale/derp-custom.yaml"}
    grep -F 'issuer: "https://idp.internal.${domain}"' ${volume "headplane" "/etc/headplane/config.yaml"}
    grep -F 'base_url: "https://searxng.internal.${domain}/"' ${volume "searxng" "/etc/searxng/settings.yml"}
    grep -F 'zone "${domain}"' ${volume "bind9" "/etc/bind"}/named.conf
    grep -F 'www        IN CNAME ${domain}.' ${volume "bind9" "/etc/bind"}/wg-public.zone
    touch "$out"
  ''
