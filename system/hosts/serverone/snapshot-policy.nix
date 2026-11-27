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

  # Keep the existing host paths and container bind mounts. Each path below
  # must be migrated to its own native ZFS mount before switching generations.
  excludedMounts = {
    "/mnt/SSD/apps/t3code/nix-root" = "ssd_pool/apps/t3code-nix-root";
    "/mnt/SSD/apps/t3code/tmp" = "ssd_pool/apps/t3code-tmp";
    "/mnt/SSD/apps/openchamber/nix-root" = "ssd_pool/apps/openchamber-nix-root";
    "/mnt/SSD/apps/openchamber/tmp" = "ssd_pool/apps/openchamber-tmp";
    "/mnt/SSD/apps/byparr/cache" = "ssd_pool/apps/byparr-cache";
    "/mnt/SSD/apps/jellyfin/cache" = "ssd_pool/apps/jellyfin-cache";
    "/mnt/SSD/apps/jackett/downloads" = "ssd_pool/apps/jackett-downloads";
    "/mnt/SSD/apps/searxng/cache" = "ssd_pool/apps/searxng-cache";
    "/mnt/SSD/apps/bind9/log" = "ssd_pool/apps/bind9-log";
    "/mnt/SSD/apps/certbot/logs" = "ssd_pool/apps/certbot-logs";
    "/mnt/SSD/apps/certbot/work" = "ssd_pool/apps/certbot-work";
    "/mnt/HDD/apps/immich/model-cache" = "hdd_pool/apps/immich-model-cache";
  };
}
