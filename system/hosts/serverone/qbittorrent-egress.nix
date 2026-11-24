{
  qbtIp,
  webPort,
  wgTable,
  homeInterface,
}:
{ pkgs, lib, ... }:
let
  unit = "qbittorrent-egress.service";
  container = "nerdctl-qbittorrent.service";
  homeFlag = "/run/torrent-egress-home";
  qbtRule = "priority 10001 from ${qbtIp}/32 table ${toString wgTable}";
  table = "ip qbittorrent_egress";
  guard =
    mode: uplink:
    pkgs.writeText "qbittorrent-egress-${mode}.nft" # nftables
      ''
        destroy table ${table}
        table ${table} {
          chain ${mode} {
            type filter hook forward priority -10; policy accept;
            ${lib.optionalString (mode == "home") ''iifname "wg0" ip daddr ${qbtIp} counter drop''}
            ip saddr ${qbtIp} oifname "tailscale0" ct direction reply tcp sport ${toString webPort} accept
            ip saddr ${qbtIp} oifname != { "${uplink}", "nerdctl0" } counter drop
          }
        }
      '';
  command = pkgs.writeShellApplication {
    name = "torrent-egress";
    runtimeInputs = [
      pkgs.nftables
      pkgs.systemd
      pkgs.util-linux
    ];
    text = # sh
      ''
        if [[ $# != 1 || ! $1 =~ ^(vps|home|status)$ ]]; then
          echo "Usage: sudo torrent-egress {vps|home|status}" >&2
          exit 2
        fi
        if ((EUID != 0)); then
          echo "Run this command with sudo." >&2
          exit 1
        fi

        exec 9>/run/torrent-egress.lock
        flock 9
        active_mode() {
          systemctl is-active --quiet ${unit} || return 1
          if nft list chain ${table} vps >/dev/null 2>&1; then
            echo vps
          elif nft list chain ${table} home >/dev/null 2>&1; then
            echo home
          else
            return 1
          fi
        }

        current=$(active_mode || true)
        if [[ $1 == status ]]; then
          if [[ -z $current ]]; then
            echo "No active qBittorrent egress policy" >&2
            exit 1
          fi
          echo "$current"
          exit 0
        fi

        if [[ $current != "$1" ]]; then
          systemctl stop ${container}
          if [[ $1 == home ]]; then
            touch ${homeFlag}
          else
            rm -f ${homeFlag}
          fi
          systemctl restart ${unit}
          systemctl start ${container}
        elif ! systemctl is-active --quiet ${container}; then
          systemctl start ${container}
        fi
        echo "qBittorrent egress: $1"
      '';
  };
in
{
  environment.systemPackages = [ command ];

  # Install the guard independently of wg0, including if its policy table is
  # empty. The container must not run without the guard.
  systemd.services.qbittorrent-egress = {
    description = "Apply the selected qBittorrent egress policy";
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
    path = [
      pkgs.conntrack-tools
      pkgs.iproute2
      pkgs.nftables
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = # sh
      ''
        if [[ -e ${homeFlag} ]]; then
          nft -f ${guard "home" homeInterface}
        else
          nft -f ${guard "vps" "wg0"}
          ip rule add ${qbtRule}
        fi

        # Remove old NAT mappings and return-path marks before the container
        # starts. Conntrack deletion returns nonzero even for an empty match.
        for selector in --orig-src --reply-src; do
          if ! conntrack -D "$selector" ${qbtIp}; then
            remaining=$(conntrack -L "$selector" ${qbtIp})
            if [[ -n $remaining ]]; then
              echo "Failed to clear qBittorrent conntrack entries" >&2
              exit 1
            fi
          fi
        done
      '';
    postStop = # sh
      ''
        ip rule del ${qbtRule} || true
        nft destroy table ${table}
      '';
  };
  systemd.services.nerdctl-qbittorrent = {
    after = [ unit ];
    bindsTo = [ unit ];
    partOf = [ unit ];
  };
}
