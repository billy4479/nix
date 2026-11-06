{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  home = "/mnt/SSD/apps/openchamber/home";
  directory = "/mnt/SSD/agent-config";
  state = "${home}/.local/state/agent-config-migration";
in
{
  config = lib.mkIf (options ? nerdctl-containers) {
    systemd.tmpfiles.rules = [
      "d ${directory} 2770 container-5021 containers - -"
      "a+ ${directory} - - - - g:admin:rwx,d:g:admin:rwx,d:u::rwx,d:g::rwx,d:o::---"
    ];
    systemd.services.agent-config-migration = {
      description = "Seed shared agent instructions and skills and redirect OpenChamber";
      requires = [ "systemd-tmpfiles-setup.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      before = [
        "nerdctl-openchamber.service"
        "nerdctl-t3code.service"
        "nerdctl-syncthing.service"
      ];
      unitConfig.RequiresMountsFor = [
        home
        directory
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "container-5021";
        Group = "containers";
        UMask = "0007";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${./migrate.py} --home ${home} --destination ${directory} --state ${state} --store /mnt/SSD/apps/openchamber/nix-root/nix/store";
      };
    };
    systemd.services.nerdctl-openchamber = {
      requires = [ "agent-config-migration.service" ];
      after = [ "agent-config-migration.service" ];
    };
    systemd.services.nerdctl-t3code = {
      requires = [ "agent-config-migration.service" ];
      after = [ "agent-config-migration.service" ];
    };
    systemd.services.nerdctl-syncthing = {
      requires = [ "agent-config-migration.service" ];
      after = [ "agent-config-migration.service" ];
    };
  };
}
