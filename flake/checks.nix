{
  pkgs,
  hosts,
  inputs,
  system,
  overlays,
  domain,
}:
{
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
  raw-firewall = import ../tests/raw-firewall.nix {
    inherit pkgs;
    ruleset = hosts.nixosConfigurations.serverone.config.polpetta.generated.rawFirewallFile;
    rawUnit = hosts.nixosConfigurations.serverone.config.systemd.services.polpetta-raw-firewall;
  };
  edge-forwarding = import ../tests/edge-forwarding.nix { inherit pkgs; };
  public-health-monitor = import ../tests/public-health-monitor.nix {
    inherit pkgs domain;
    vps = hosts.nixosConfigurations.vps-proxy.config;
  };
}
