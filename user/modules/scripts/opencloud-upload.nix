{
  domain,
  pkgs,
  lib,
  ...
}:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "opencloud-upload";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
      ];
      text = # sh
      ''
        origin=${lib.escapeShellArg "https://opencloud.${domain}"}
      ''
      + builtins.readFile ./opencloud-upload.sh;
    })
  ];
}
