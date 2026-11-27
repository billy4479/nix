{
  pkgs,
  lib,
  options,
  ...
}:
{
  # TODO: Not sure if this is needed
  networking.firewall = lib.mkIf (options ? nerdctl-containers) {
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
  };

  polpetta.services.syncthing = {
    container = {
      entrypoint = [ (lib.getExe pkgs.syncthing) ];
      environment = {
        HOME = "/var/syncthing";
        STHOMEDIR = "/var/syncthing/config";
        STGUIADDRESS = "0.0.0.0:8384";
      };
      ports = [
        "22000:22000/tcp"
        "22000:22000/udp"
        "21027:21027/udp"
      ];

      volumes = [
        {
          hostPath = "/mnt/SSD/apps/syncthing";
          containerPath = "/var/syncthing/config";
        }
        {
          hostPath = "/mnt/HDD/apps/syncthing";
          containerPath = "/var/syncthing/Sync";
        }
        {
          hostPath = "/mnt/SSD/apps/workspaces/code";
          sharedDataset = "workspaces";
          containerPath = "/var/syncthing/Sync/code";
        }
        {
          hostPath = "/mnt/SSD/apps/workspaces/nix";
          sharedDataset = "workspaces";
          containerPath = "/var/syncthing/Sync/nix";
        }
        {
          hostPath = "/mnt/SSD/agent-config";
          sharedDataset = "agent-config";
          containerPath = "/var/syncthing/Sync/agent-config";
          # Shared with T3 Code; retain the migration's ownership/ACLs.
          customPermissionScript = ":";
        }
      ];

      id = 2;
      # T3 Code and Syncthing must both own synchronized workspace files so
      # that permission synchronization does not revoke either service's access.
      uid = 5021;
    };

    # Host-published only; no VPS forward. Preserve existing peer reachability.
    raw = [
      {
        port = 22000;
        access = "local";
        allowedSources = [ "0.0.0.0/0" ];
      }
      {
        port = 22000;
        proto = "udp";
        access = "local";
        allowedSources = [ "0.0.0.0/0" ];
      }
      {
        port = 21027;
        proto = "udp";
        access = "local";
        allowedSources = [ "0.0.0.0/0" ];
      }
    ];

    web = {
      port = 8384;
      access = "admin-only";
      probe.path = "/rest/noauth/health";
    };
  };
}
