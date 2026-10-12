{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.polpetta;
  services = config.polpetta.services;

  containerSubmodule = import ../containers/container-options.nix { inherit lib; };

  hasContainers = options ? nerdctl-containers;

  servicesWithWeb = lib.filterAttrs (_: svc: svc.web != null) services;

  domainOf =
    name: svc:
    if svc.web.domain != null then
      svc.web.domain
    else if svc.web.access == "public" then
      "${name}.polpetta.online"
    else
      "${name}.internal.polpetta.online";

  rawEntries = lib.concatMap (
    name: map (raw: { inherit name raw; id = services.${name}.container.id; }) services.${name}.raw
  ) (lib.attrNames services);

  publicRawEntries = lib.filter (e: e.raw.access == "public") rawEntries;
  recordEntries = lib.filter (e: e.raw.record != null) rawEntries;

  remotePortOf = raw: if raw.remotePort == null then raw.port else raw.remotePort;

  # The frp edge must not be able to reach restricted tiers; nginx enforces
  # on the proxy_protocol-restored client address, so ordering matters.
  externalIp =
    if cfg.externalTrafficFrom != null then
      cfg.externalTrafficFrom
    else
      throw "polpetta.services: a non-public web endpoint exists but polpetta.externalTrafficFrom is null (it is set by the nginx container definition)";

  aclLines =
    access:
    if access == "public" then
      [ ]
    else
      [ "  deny ${externalIp};" ]
      ++ lib.optionals (access == "tailnet") [ "  allow 100.64.0.0/10;" ]
      ++ [
        "  allow 10.0.0.0/8;"
        "  allow 192.168.0.0/16;"
        "  deny all;"
      ];

  vhostLines =
    name: svc:
    let
      web = svc.web;
      extraLines = lib.filter (l: l != "") (
        lib.optionals (web.nginx.extraConfig != "") (
          lib.splitString "\n" web.nginx.extraConfig
        )
      );
    in
    [
      "server {"
      "  listen 443 ssl;"
      "  listen 4443 ssl proxy_protocol;"
      "  http2 on;"
      ""
      "  server_name ${domainOf name svc};"
      ""
      "  include /etc/nginx/snippets/tls.conf;"
      "  include /etc/nginx/snippets/headers.conf;"
    ]
    ++ map (l: "    ${l}") (aclLines web.access)
    ++ [
      "  location / {"
      "    include /etc/nginx/snippets/proxy.conf;"
    ]
    ++ map (l: "      ${l}") extraLines
    ++ [
      "  }"
      "}"
    ];

  # proxy.conf resolves its upstream through $backend; the map must live in
  # the generated file since the hand-written one was removed and generated
  # vhosts must coexist with the legacy wildcard+map blocks during migration.
  backendMapLines = map (
    name:
    let
      svc = services.${name};
    in
    "  ${domainOf name svc}  10.0.1.${toString svc.container.id}:${toString svc.web.port};"
  ) (lib.attrNames servicesWithWeb);

  nginxVhostsText =
    lib.concatStringsSep "\n" (
      [
        "# Generated from polpetta.services. Do not edit."
        ""
      ]
      ++ lib.optionals (servicesWithWeb != { }) (
        [
          "map $host $backend {"
        ]
        ++ backendMapLines
        ++ [
          "  default \"\";"
          "}"
          ""
        ]
        ++ lib.concatMap (
          name: vhostLines name services.${name} ++ [ "" ]
        ) (lib.attrNames servicesWithWeb)
      )
    );

  proxyName =
    name: raw:
    "${name}-${toString raw.port}" + lib.optionalString (raw.proto == "udp") "-udp";

  frpcProxy =
    e:
    # toml
    ''
      [[proxies]]
      name = "${proxyName e.name e.raw}"
      type = "${e.raw.proto}"
      localIP = "10.0.1.${toString e.id}"
      localPort = ${toString e.raw.port}
      remotePort = ${toString (remotePortOf e.raw)}
    '';

  frpcProxies = lib.concatStringsSep "\n" (map frpcProxy publicRawEntries);

  # allowPorts ranges are not proto-aware, so the same port over tcp and udp
  # yields a single range.
  frpsAllowPorts = lib.concatStringsSep "\n" (
    map (port: "  { start = ${toString port}, end = ${toString port} },") (
      lib.unique (map (e: remotePortOf e.raw) publicRawEntries)
    )
  );

  frpsTcpPorts = map (e: remotePortOf e.raw) (lib.filter (e: e.raw.proto == "tcp") publicRawEntries);
  frpsUdpPorts = map (e: remotePortOf e.raw) (lib.filter (e: e.raw.proto == "udp") publicRawEntries);

  bind9Records =
    # bind zone
    ''
      ; Generated from polpetta.services raw entries with a `record`.
      ; Included from wg-public.zone; change services, not this file.

      ${lib.concatStringsSep "\n" (
        map (e: "${e.raw.record} IN A 10.0.1.${toString e.id}") recordEntries
      )}
    '';

  duplicates =
    list:
    lib.attrNames (lib.filterAttrs (_: v: lib.length v > 1) (lib.groupBy (x: x) list));

  webDomains = lib.mapAttrsToList domainOf servicesWithWeb;
  publicDomains = lib.mapAttrsToList domainOf (
    lib.filterAttrs (_: svc: svc.web.access == "public") servicesWithWeb
  );
  nonPublicDomains = lib.mapAttrsToList domainOf (
    lib.filterAttrs (_: svc: svc.web.access != "public") servicesWithWeb
  );

  assertionEntries =
    let
      nameRe = "[a-zA-Z0-9][a-zA-Z0-9_.-]*";
    in
    [
      {
        assertion = lib.all (name: builtins.match nameRe name != null) (lib.attrNames services);
        message = "polpetta.services: service names must match ${nameRe}";
      }
      {
        assertion = duplicates webDomains == [ ];
        message = "polpetta.services: duplicate web domains: ${lib.concatStringsSep ", " (duplicates webDomains)}";
      }
      {
        assertion = duplicates (map (e: "${e.raw.proto}-${toString (remotePortOf e.raw)}") rawEntries) == [ ];
        message = "polpetta.services: duplicate remote ports: ${
          lib.concatStringsSep ", " (duplicates (map (e: "${e.raw.proto}-${toString (remotePortOf e.raw)}") rawEntries))
        }";
      }
      {
        assertion = duplicates (map (e: e.raw.record) recordEntries) == [ ];
        message = "polpetta.services: duplicate record names: ${
          lib.concatStringsSep ", " (duplicates (map (e: e.raw.record) recordEntries))
        }";
      }
      {
        assertion = lib.all (
          d: lib.hasSuffix ".polpetta.online" d && !lib.hasSuffix ".internal.polpetta.online" d
        ) publicDomains;
        message = "polpetta.services: public web domains must be under .polpetta.online and not under .internal.polpetta.online: ${
          lib.concatStringsSep ", " publicDomains
        }";
      }
      {
        assertion = lib.all (d: lib.hasSuffix ".internal.polpetta.online" d) nonPublicDomains;
        message = "polpetta.services: non-public web domains must be under .internal.polpetta.online: ${
          lib.concatStringsSep ", " nonPublicDomains
        }";
      }
    ];
in
{
  options.polpetta = {
    services = lib.mkOption {
      description = "Service definitions: one container plus its exposure.";
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              container = lib.mkOption {
                type = containerSubmodule;
                description = "The service's single container (mirrored into nerdctl-containers).";
              };

              web = lib.mkOption {
                description = "Proxied HTTP endpoint; its presence generates the nginx vhost.";
                default = null;
                type = lib.types.nullOr (
                  lib.types.submodule {
                    options = {
                      port = lib.mkOption {
                        type = lib.types.port;
                        description = "Port the application listens on inside the container.";
                      };

                      access = lib.mkOption {
                        type = lib.types.enum [
                          "public"
                          "tailnet"
                          "local"
                        ];
                        description = "Who can reach this endpoint.";
                      };

                      domain = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                        description = ''
                          Override the default domain: <name>.polpetta.online for
                          public services, <name>.internal.polpetta.online otherwise.
                        '';
                      };

                      nginx.extraConfig = lib.mkOption {
                        type = lib.types.lines;
                        default = "";
                        description = "Raw nginx directives injected into the generated location / block.";
                      };
                    };
                  }
                );
              };

              raw = lib.mkOption {
                description = "Raw TCP/UDP port forwards, independent of the web endpoint.";
                default = [ ];
                type = lib.types.listOf (
                  lib.types.submodule {
                    options = {
                      port = lib.mkOption {
                        type = lib.types.port;
                        description = "Port the application listens on inside the container.";
                      };

                      proto = lib.mkOption {
                        type = lib.types.enum [
                          "tcp"
                          "udp"
                        ];
                        default = "tcp";
                        description = "Protocol to forward.";
                      };

                      access = lib.mkOption {
                        type = lib.types.enum [
                          "public"
                          "tailnet"
                          "local"
                        ];
                        description = "Who can reach this port.";
                      };

                      remotePort = lib.mkOption {
                        type = lib.types.nullOr lib.types.port;
                        default = null;
                        description = "Port opened on the vps; defaults to port.";
                      };

                      record = lib.mkOption {
                        type = lib.types.nullOr (lib.types.strMatching "[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?");
                        default = null;
                        description = "bind9 record name pointing at the container IP.";
                      };
                    };
                  }
                );
              };
            };
          }
        )
      );
    };

    externalTrafficFrom = lib.mkOption {
      description = "The IP frp tunnels arrive from (set by the nginx container definition); used for ACLs.";
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    generated = {
      nginxVhostsFile = lib.mkOption {
        description = "nginx vhosts generated from all web endpoints.";
        type = lib.types.package;
        readOnly = true;
      };

      frpcProxies = lib.mkOption {
        description = "toml fragment with the frpc proxies for public raw ports.";
        type = lib.types.str;
        readOnly = true;
      };

      frpsAllowPorts = lib.mkOption {
        description = "toml fragment for the frps allowPorts list.";
        type = lib.types.str;
        readOnly = true;
      };

      frpsTcpPorts = lib.mkOption {
        description = "Public raw TCP ports to open in the vps firewall.";
        type = lib.types.listOf lib.types.int;
        readOnly = true;
      };

      frpsUdpPorts = lib.mkOption {
        description = "Public raw UDP ports to open in the vps firewall.";
        type = lib.types.listOf lib.types.int;
        readOnly = true;
      };

      bind9Records = lib.mkOption {
        description = "bind9 zone records fragment for raw entries with a record.";
        type = lib.types.str;
        readOnly = true;
      };
    };
  };

  config = {
    assertions = assertionEntries;

    polpetta.generated = {
      frpsAllowPorts = frpsAllowPorts;
      frpsTcpPorts = frpsTcpPorts;
      frpsUdpPorts = frpsUdpPorts;

      nginxVhostsFile = lib.mkIf hasContainers (
        pkgs.writeText "polpetta-services-vhosts.conf" nginxVhostsText
      );
      frpcProxies = lib.mkIf hasContainers frpcProxies;
      bind9Records = lib.mkIf hasContainers bind9Records;
    };
  }
  // lib.optionalAttrs hasContainers {
    nerdctl-containers = lib.mapAttrs (
      name: svc: svc.container // lib.optionalAttrs (svc.web != null) { useNginx = true; }
    ) services;
  };
}
