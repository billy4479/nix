# The Boolean values are for automatic snapshots, not manual snapshots.
{
  datasets = {
    zroot = false;
    "zroot/root" = false;
    "zroot/nix" = false;
    hdd_pool = false;
    "hdd_pool/apps" = true;
    "hdd_pool/generic" = true;
    "hdd_pool/timemachine" = true;
    "hdd_pool/torrent" = true;
    ssd_pool = false;
    "ssd_pool/agent-vm" = false;
    "ssd_pool/apps" = true;
    "ssd_pool/generic" = true;
    "ssd_pool/minecraft" = true;
    "ssd_pool/vm" = true;
  };

  mounts = {
    "/" = "zroot/root";
    "/mnt/HDD/apps" = "hdd_pool/apps";
    "/mnt/HDD/generic" = "hdd_pool/generic";
    "/mnt/HDD/timemachine" = "hdd_pool/timemachine";
    "/mnt/HDD/torrent" = "hdd_pool/torrent";
    "/mnt/SSD/apps" = "ssd_pool/apps";
    "/mnt/SSD/generic" = "ssd_pool/generic";
    "/mnt/SSD/minecraft" = "ssd_pool/minecraft";
    "/mnt/SSD/vm" = "ssd_pool/vm";
  };

  shared = {
    torrent = {
      path = "/mnt/HDD/torrent";
      dataset = "hdd_pool/torrent";
    };
    hdd-generic = {
      path = "/mnt/HDD/generic";
      dataset = "hdd_pool/generic";
    };
    minecraft = {
      path = "/mnt/SSD/minecraft";
      dataset = "ssd_pool/minecraft";
    };
    certificates = {
      path = "/mnt/SSD/apps/certbot/config";
    };
    workspaces = {
      path = "/mnt/SSD/apps/workspaces";
    };
    agent-config = {
      path = "/mnt/SSD/agent-config";
      dataset = "ssd_pool/agent-config";
    };
  };

  # Temporary rollout inventory. Remove a path only after the operator has
  # migrated it or confirmed that it is safe to provision empty. New paths
  # are not added here. Existing shared datasets need no migration entry.
  pending = [
    "/mnt/HDD/apps/immich/model-cache"
    "/mnt/HDD/apps/immich/upload"
    "/mnt/HDD/apps/mc-runner/Friends-Git"
    "/mnt/HDD/apps/opencloud"
    "/mnt/HDD/apps/syncthing"
    "/mnt/SSD/agent-config"
    "/mnt/SSD/apps/agent-up"
    "/mnt/SSD/apps/bind9/cache"
    "/mnt/SSD/apps/bind9/lib"
    "/mnt/SSD/apps/bind9/log"
    "/mnt/SSD/apps/byparr/cache"
    "/mnt/SSD/apps/certbot/config"
    "/mnt/SSD/apps/certbot/logs"
    "/mnt/SSD/apps/certbot/work"
    "/mnt/SSD/apps/ff"
    "/mnt/SSD/apps/game-server-runner"
    "/mnt/SSD/apps/giuoco-del-divertimento"
    "/mnt/SSD/apps/grafana/lib"
    "/mnt/SSD/apps/heascale/headplane"
    "/mnt/SSD/apps/heascale/lib"
    "/mnt/SSD/apps/heascale/run"
    "/mnt/SSD/apps/immich/valkey"
    "/mnt/SSD/apps/jackett/config"
    "/mnt/SSD/apps/jackett/downloads"
    "/mnt/SSD/apps/jellyfin/cache"
    "/mnt/SSD/apps/jellyfin/config"
    "/mnt/SSD/apps/laurea"
    "/mnt/SSD/apps/lunamultiplayer"
    "/mnt/SSD/apps/mircrewrr"
    "/mnt/SSD/apps/opencloud/apps"
    "/mnt/SSD/apps/opencloud/config"
    "/mnt/SSD/apps/outline/data"
    "/mnt/SSD/apps/outline/valkey"
    "/mnt/SSD/apps/postgresql/18"
    "/mnt/SSD/apps/qbittorrent"
    "/mnt/SSD/apps/quote-bot"
    "/mnt/SSD/apps/radarr"
    "/mnt/SSD/apps/radicale"
    "/mnt/SSD/apps/searxng/cache"
    "/mnt/SSD/apps/seerr"
    "/mnt/SSD/apps/sonarr"
    "/mnt/SSD/apps/syncthing"
    "/mnt/SSD/apps/t3code/home"
    "/mnt/SSD/apps/t3code/tmp"
    "/mnt/SSD/apps/tsidp/lib"
  ];
}
