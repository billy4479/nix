{
  pkgs,
  domain,
  adminAddress,
  preview,
}:
[
  {
    hostPath = "${pkgs.replaceVars ./headscale.yaml { inherit domain; }}";
    containerPath = "/etc/headscale/config.yaml";
    readOnly = true;
  }
  {
    hostPath = "${pkgs.writeText "policy.json" (
      builtins.toJSON (import ./policy.nix { inherit adminAddress preview; })
    )}";
    containerPath = "/etc/headscale/policy.hujson";
    readOnly = true;
  }
]
