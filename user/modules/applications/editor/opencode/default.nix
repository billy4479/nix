{
  pkgs,
  config,
  lib,
  flakeInputs,
  ...
}:
let
  artifacts = import ./artifacts.nix { inherit pkgs flakeInputs; };
  opencodeWrapped = artifacts.package;
in
{
  home.packages = [ opencodeWrapped ];
  systemd.user.services.opencode = {
    Unit = {
      Description = "opencode headless web server";
      Documentation = [ "https://opencode.ai/docs/" ];
    };

    Service = {
      ExecStart = lib.escapeShellArgs [
        "${opencodeWrapped}/bin/opencode"
        "serve"
        "--hostname"
        "127.0.0.1"
        "--port"
        "4096"
      ];
      WorkingDirectory = config.home.homeDirectory;
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  home.file = {
    "${config.xdg.configHome}/opencode" = {
      source = artifacts.config;
      recursive = true;
    };
    "${config.home.homeDirectory}/.agents/skills" = {
      source = artifacts.skills;
      recursive = true;
    };
  };
}
