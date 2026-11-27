{
  pkgs,
  hosts,
  inputs,
  system,
  overlays,
  domain,
}:
{
  agent-vm = (pkgs.callPackage ../packages/agent-vm { }).tests.broker;
  agent-preview = pkgs.callPackage ../packages/agent-preview { };
  radicale =
    let
      server = hosts.nixosConfigurations.serverone.config;
      service = server.polpetta.services.radicale;
      runtime = import ../services/services/radicale/runtime.nix { inherit pkgs; };
    in
    assert service.web.access == "tailnet-only";
    pkgs.runCommand "radicale-test" { } # sh
      ''
        ${runtime}/bin/python ${../services/services/radicale}/test_landing.py ${service.container.environment.RADICALE_CONFIG}
        touch "$out"
      '';
  nix-settings = import ../tests/nix-settings.nix {
    inherit pkgs hosts;
  };
  domain = import ../tests/domain.nix {
    inherit pkgs;
    mkHosts =
      domain:
      import ./system.nix {
        inherit
          system
          inputs
          overlays
          domain
          ;
      };
  };
  shell-syntax = import ../tests/shell-syntax.nix {
    inherit pkgs;
    hosts = {
      serverone = hosts.nixosConfigurations.serverone.config;
      vps-proxy = hosts.nixosConfigurations.vps-proxy.config;
    };
  };
  container-images = import ../tests/container-images.nix {
    inherit pkgs;
    serverone = hosts.nixosConfigurations.serverone.config;
  };
  certbot = import ../tests/certbot.nix {
    inherit pkgs;
    serverone = hosts.nixosConfigurations.serverone.config;
  };
  server-policy = import ../tests/server-policy.nix {
    inherit pkgs;
    serverone = hosts.nixosConfigurations.serverone.config;
    vps = hosts.nixosConfigurations.vps-proxy.config;
  };
  monitoring = import ../tests/monitoring.nix {
    inherit pkgs domain;
    ruleFiles = hosts.nixosConfigurations.serverone.config.services.prometheus.ruleFiles;
    scrapeConfigs = hosts.nixosConfigurations.serverone.config.services.prometheus.scrapeConfigs;
    blackboxConfig =
      hosts.nixosConfigurations.serverone.config.services.prometheus.exporters.blackbox.configFile;
  };
  package-updates =
    pkgs.runCommand "package-updates-test"
      {
        nativeBuildInputs = with pkgs; [
          python3
          bash
          git
        ];
      }
      # sh
      ''
        python ${../tests/package-updates.py} ${../packages}
        touch "$out"
      '';
  derp-certificates = pkgs.callPackage ../services/derp-certificates/test.nix { };
  private-store-threshold = pkgs.callPackage ../containers/private-store-wipe/test.nix { };
  agent-containers = import ../services/pi/test.nix { inherit pkgs; };
  mail-watch = import ../services/mail-watch/test.nix { inherit pkgs; };
  agent-browser = import ../tests/agent-browser.nix {
    inherit pkgs;
    flakeInputs = inputs;
  };
  raw-firewall =
    let
      serverone = hosts.nixosConfigurations.serverone;
      # Exercise both states even when the deployed host has admin ingress enabled.
      disabled =
        (serverone.extendModules {
          modules = [ { polpetta.adminIngressEnabled = pkgs.lib.mkForce false; } ];
        }).config;
      enabled =
        (serverone.extendModules {
          modules = [
            {
              polpetta.adminIngressEnabled = pkgs.lib.mkForce true;
              polpetta.agentPreview.enable = true;
            }
          ];
        }).config;
    in
    import ../tests/raw-firewall.nix {
      inherit pkgs;
      ruleset = disabled.polpetta.generated.rawFirewallFile;
      adminRuleset = enabled.polpetta.generated.rawFirewallFile;
      rawUnit = disabled.systemd.services.polpetta-raw-firewall;
      prometheusTable =
        hosts.nixosConfigurations.serverone.config.networking.nftables.tables.serverone-prometheus;
      prometheusInputRules =
        hosts.nixosConfigurations.serverone.config.networking.firewall.extraInputRules;
      cniConfig =
        builtins.fromJSON
          hosts.nixosConfigurations.serverone.config.environment.etc."cni/net.d/10-nerdctl.conflist".text;
    };
  edge-forwarding = import ../tests/edge-forwarding.nix { inherit pkgs; };
  public-health-monitor = import ../tests/public-health-monitor.nix {
    inherit pkgs domain;
    vps = hosts.nixosConfigurations.vps-proxy.config;
  };
}
