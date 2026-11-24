{
  config,
  pkgs,
  domain,
  lib,
  options,
  ...
}:
let
  # The host path keeps a historical `heascale` typo; data lives there.
  baseDir = "/mnt/SSD/apps/heascale";
  headscaleFiles = import ./files.nix {
    inherit pkgs domain;
    adminAddress = config.polpetta.generated.adminIngress.address;
  };
in
{
  # headscale forwards tailnet traffic into the nerdctl bridge (subnet router).
  boot.kernel.sysctl = lib.mkIf (options ? nerdctl-containers) {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  polpetta.services.headscale = {
    container = {
      id = 15;

      # Keep the administration CLI on PATH for exec-in-container.
      copyToRoot = [ pkgs.headscale ];
      entrypoint = [ (lib.getExe pkgs.headscale) ];
      cmd = [ "serve" ];

      volumes = headscaleFiles ++ [
        {
          hostPath = "${baseDir}/lib";
          containerPath = "/var/lib/headscale";
        }
        {
          hostPath = "${baseDir}/run";
          containerPath = "/var/run/headscale";
        }
        {
          hostPath = "${pkgs.replaceVars ./derp-custom.yaml { inherit domain; }}";
          containerPath = "/etc/headscale/derp-custom.yaml";
          readOnly = true;
        }
      ];
    };

    # Tailnet clients reach the control plane from the internet.
    web = {
      port = 8080;
      access = "public";
      probe.path = "/health";
    };
  };
}
