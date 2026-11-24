{
  pkgs,
  domain,
  adminAddress,
}:
[
  {
    hostPath = "${pkgs.replaceVars ./headscale.yaml { inherit domain; }}";
    containerPath = "/etc/headscale/config.yaml";
    readOnly = true;
  }
  {
    hostPath = "${pkgs.writeText "policy.json" (
      builtins.toJSON (import ./policy.nix { inherit adminAddress; })
    )}";
    containerPath = "/etc/headscale/policy.hujson";
    readOnly = true;
  }
]
