# The complete service set, imported by every host that evaluates
# polpetta.services (serverone runs the containers; the vps only consumes the
# frps/firewall/dns projection). Keeping a single import list here guarantees
# both hosts always agree on the service set; a service defined but imported
# on only one host would silently lose its vps-side projection.
{
  imports = [
    ../module.nix

    ./bind9
    ./syncthing.nix
    ./immich-server.nix
    ./postgresql
    ./immich-ml.nix
    ./immich-redis.nix
    ./qbittorrent.nix

    ./radarr.nix
    ./jackett.nix
    ./sonarr.nix
    ./byparr.nix

    ./jellyfin.nix

    ./bentopdf.nix
    ./opencloud.nix
    ./searxng
    ./openchamber.nix

    ./game-server-runner
    ./lunamultiplayer.nix
    ./calendar-proxy.nix
    ./ff.nix
    ./giuoco-del-divertimento.nix
    ./agent-up.nix
    ./quote-bot.nix

    ./outline.nix
    ./outline-valkey.nix
    ./tsidp.nix

    ./grafana
    ./headscale
    ./headplane
  ];
}
