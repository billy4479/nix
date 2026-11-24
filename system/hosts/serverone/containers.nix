{
  config,
  lib,
  pkgs,
  ...
}:
let
  deniedExecContainers = [ ];
  allowedExecContainerConfigs = removeAttrs config.nerdctl-containers deniedExecContainers;
  allowedExecContainers = lib.mapAttrs (_: container: container.uid) allowedExecContainerConfigs;
  safeExecCapabilities = [ "CAP_NET_BIND_SERVICE" ];
  hasSecurityOption =
    option:
    builtins.match "--(cap-add|cap-drop|privileged|security-opt)(=.*|[[:space:]].*)?" option != null;
  execInContainer = pkgs.callPackage ../../../containers/exec-in-container {
    allowedContainers = allowedExecContainers;
  };
  rawFirewallRemoval =
    pkgs.writeText "remove-polpetta-raw.nft" # nftables
      ''
        destroy table inet polpetta_raw
        destroy table bridge polpetta_raw
      '';
in
{
  imports = [
    ../../../containers/module.nix

    ../../../containers/certbot.nix
    ../../../containers/nginx

    ../../../services/services
  ];

  environment.systemPackages = [
    execInContainer
    pkgs.nerdctl
    pkgs.cni-plugins
  ];

  assertions = [
    {
      assertion = lib.all (name: builtins.hasAttr name config.nerdctl-containers) deniedExecContainers;
      message = "Every denied exec container must exist in nerdctl-containers.";
    }
    {
      assertion = lib.all (name: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" name != null) (
        builtins.attrNames allowedExecContainers
      );
      message = "Container names exposed by exec-in-container must be valid nerdctl names.";
    }
    {
      assertion = lib.all (uid: uid > 0 && uid <= 2147483647) (builtins.attrValues allowedExecContainers);
      message = "Container UIDs exposed by exec-in-container must be positive signed 32-bit integers.";
    }
    {
      assertion = lib.all (container: container.runByUser) (
        builtins.attrValues allowedExecContainerConfigs
      );
      message = "Containers exposed by exec-in-container must run as their configured non-root user.";
    }
    {
      assertion = lib.all (container: container.noNewPrivileges) (
        builtins.attrValues allowedExecContainerConfigs
      );
      message = "Containers exposed by exec-in-container must set no-new-privileges.";
    }
    {
      assertion = lib.all (
        container: lib.subtractLists safeExecCapabilities container.capabilities == [ ]
      ) (builtins.attrValues allowedExecContainerConfigs);
      message = "Containers with privilege-changing capabilities must be denied exec-in-container access.";
    }
    {
      assertion = lib.all (container: !lib.any hasSecurityOption container.extraOptions) (
        builtins.attrValues allowedExecContainerConfigs
      );
      message = "Containers exposed by exec-in-container must configure security through module options.";
    }
  ];

  system.build.execInContainer = execInContainer;

  security.sudo.extraRules = [
    {
      users = [ "billy" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/exec-in-container";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  services.nix-snapshotter = {
    enable = true;
  };

  virtualisation.containerd = {
    enable = true;
    nixSnapshotterIntegration = true;
  };

  # Keep the independent raw-port policy installed across ordinary firewall
  # reloads. Requires/ordering fail closed before any container can start;
  # reloading this unit atomically replaces both nft tables without a gap.
  systemd.services.polpetta-raw-firewall = {
    description = "Isolate declared container raw endpoints";
    wantedBy = [ "multi-user.target" ];
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    before = [ "containerd.service" ];
    reloadIfChanged = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${config.polpetta.generated.rawFirewallFile}";
      ExecReload = "${pkgs.nftables}/bin/nft -f ${config.polpetta.generated.rawFirewallFile}";
      ExecStop = "${pkgs.nftables}/bin/nft -f ${rawFirewallRemoval}";
    };
  };
  systemd.services.containerd.requires = [ "polpetta-raw-firewall.service" ];

  # nerdctl 2.4 checks published ports via iptables even for an nft CNI
  # network. Use the serverone-only build that finds CNI's nft mappings.
  nixpkgs.overlays = [ (import ./nerdctl-nftables.nix) ];

  environment.etc = {
    "nerdctl/nerdctl.toml".text = # toml
      ''
        address = "unix:///run/containerd/containerd.sock"
        namespace = "default"
        snapshotter = "nix"

        cni_path = "${pkgs.cni-plugins}/bin"
        cni_netconfpath = "/etc/cni/net.d"
      '';

    "containerd/config.toml".text = # toml
      ''
        version = 2

        [proxy_plugins]
          [proxy_plugins.nix]
            type = "snapshot"
            address = "/run/nix-snapshotter/nix-snapshotter.sock"

        # Needed so image unpack/import uses nix-snapshotter for the target platform(s)
        [plugins."io.containerd.transfer.v1.local"]
          [[plugins."io.containerd.transfer.v1.local".unpack_config]]
            platform = "linux/amd64"
            snapshotter = "nix"

        # Optional (only relevant to CRI/Kubernetes; harmless if CRI is enabled but you don't use it)
        [plugins."io.containerd.grpc.v1.cri".containerd]
          snapshotter = "nix"
      '';

    "cni/net.d/10-nerdctl.conflist".text = builtins.toJSON {
      cniVersion = "1.0.0";
      name = "nerdctl-bridge";
      # Prevent an unqualified nerdctl run from autogenerating a second,
      # iptables-backed default bridge.
      nerdctlLabels."nerdctl/default-network" = "true";
      plugins = [
        {
          type = "bridge";
          bridge = "nerdctl0";
          isGateway = true;
          # firewall.nix owns egress masquerading and its WireGuard exception.
          ipMasq = false;
          hairpinMode = true;
          ipam = {
            type = "host-local";
            routes = [ { dst = "0.0.0.0/0"; } ];
            ranges = [
              [
                {
                  subnet = "10.0.1.0/24";
                  gateway = "10.0.1.1";
                }
              ]
            ];
          };
        }
        {
          type = "portmap";
          backend = "nftables";
          capabilities = {
            portMappings = true;
          };
        }
        # CNI's firewall plugin has no native nft backend. NixOS handles
        # forwarding, and polpetta_raw still enforces endpoint access tiers.
        { type = "tuning"; }
      ];
    };
  };
}
