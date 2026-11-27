{
  adminAddress,
  preview ? {
    enable = false;
  },
}:
let
  adminHttps = "${adminAddress}:443";
  previewTestPorts =
    if preview.enable then
      [
        "${adminAddress}:20000"
        "${adminAddress}:20063"
      ]
    else
      [ ];
  serverTag = "tag:serverone";
in
{
  hosts.tailnet-v6 = "fd7a:115c:a1e0::/48";
  groups."group:admin" = [ "jack@" ];

  acls = [
    {
      # Preserve existing tailnet, subnet and exit-node access without
      # granting everyone access to the dedicated admin IP.
      action = "accept";
      src = [ "*" ];
      dst = [
        "100.64.0.0/10:*"
        "tailnet-v6:*"
        "10.0.1.0/24:*"
        "192.168.2.0/24:*"
        "autogroup:internet:*"
      ];
    }
    {
      action = "accept";
      src = [ "group:admin" ];
      dst = [ adminHttps ];
      proto = "tcp";
    }
  ]
  ++ (
    if preview.enable then
      map (proto: {
        action = "accept";
        src = [ "group:admin" ];
        dst = [ "${adminAddress}:${preview.rawRange}" ];
        inherit proto;
      }) preview.protocols
    else
      [ ]
  );

  tagOwners = {
    "tag:idp" = [ "jack@" ];
    # Only a Headscale operator should assign this infrastructure tag.
    ${serverTag} = [ ];
  };
  autoApprovers.routes."${adminAddress}/32" = [ serverTag ];

  grants = [
    {
      src = [ "jack@" ];
      dst = [ "tag:idp" ];
      app."tailscale.com/cap/tsidp" = [
        {
          allow_admin_ui = true;
          allow_dcr = true;
          includeInUserInfo = true;
          extraClaims.grafana_role = "Admin";
        }
      ];
    }
  ];

  tests = [
    {
      src = "jack@";
      accept = [ adminHttps ] ++ previewTestPorts;
      deny = [
        "${adminAddress}:8443"
        "${adminAddress}:19999"
        "${adminAddress}:20064"
      ];
    }
    {
      src = "luke@";
      accept = [
        "10.0.1.6:443"
        "10.0.1.11:53"
      ];
      deny = [ adminHttps ] ++ previewTestPorts;
    }
  ]
  ++
    map
      (src: {
        inherit src;
        deny = [ adminHttps ] ++ previewTestPorts;
      })
      [
        "edo@"
        "costi@"
        "tag:idp"
        serverTag
      ];
}
