{ lib, options, ... }:
let
  directory = "/mnt/SSD/agent-config";
in
{
  config = lib.mkIf (options ? nerdctl-containers) {
    systemd.tmpfiles.rules = [
      "d ${directory} 2770 container-5021 containers - -"
      "a+ ${directory} - - - - g:admin:rwx,d:g:admin:rwx,d:u::rwx,d:g::rwx,d:o::---"
    ];
  };
}
