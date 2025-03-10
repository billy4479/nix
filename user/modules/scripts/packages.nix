{
  pkgs,
  lib,
  config,
  extraConfig,
  ...
}:
let
  home = config.home.homeDirectory;
  dmenu = "${lib.getExe (if extraConfig.wayland then pkgs.rofi-wayland else pkgs.rofi)} -i -dmenu";

  zenity = lib.getExe pkgs.zenity;

  mpv = lib.getExe pkgs.mpv;

  fd = lib.getExe pkgs.fd;
  xdg-open = "${pkgs.xdg-utils}/bin/xdg-open";

  wg = lib.getExe pkgs.wireguard-tools;

  maim = lib.getExe pkgs.maim;
  copyCmd = "${lib.getExe pkgs.xclip} -selection clipboard -t image/png";
  xdotool = lib.getExe pkgs.xdotool;
in
{
  mpv-url =
    pkgs.writeScriptBin "mpv-url"
      # sh
      ''
        #!/bin/sh
        set -euxo pipefail

        ${zenity} --entry \
          --text="Enter video URL" \
          --title="MPV URL player" \
          --ok-label="Play" |
          xargs ${mpv}
      '';

  open-document =
    let
      dirs = lib.strings.concatMapStringsSep " " (x: "\"${x}\"") [
        "${config.xdg.userDirs.download}"
        "${home}/code"
      ];
    in
    pkgs.writeScriptBin "open-document"
      # sh
      ''
        #!/bin/sh
        set -euxo pipefail

        files=$(${fd} --extension=pdf -I . ${dirs})
        files=$(echo "$files" | sed "s,$HOME/,,g")
        selection=$(echo "$files" | ${dmenu})
        echo "$selection" |
          xargs --delimiter '\n' printf "$HOME/%s\n" |
          xargs --delimiter '\n' ${xdg-open}
      '';

  generate-wg-config =
    pkgs.writeScriptBin "generate-wg-config"
      # sh
      ''
        #!/bin/sh
        set -euo pipefail

        # TODO: This args parsing sucks
        serverPubkey=$1
        serverIP=$2
        addr=$3
        name=$4

        # wg0 is split
        # wg1 is full
        # Add to network-manager with
        # nmcli connection import type wireguard file wg0.conf
        # nmcli connection import type wireguard file wg1.conf

        mkdir -p $name

        key=$(${wg} genkey)
        pubKey=$(echo $key | ${wg} pubkey)

        echo "[Interface]
        PrivateKey = $key
        Address = 10.0.253.$addr/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = $serverPubkey
        Endpoint = $serverIP:51820
        AllowedIPs = 10.0.0.1/32, 10.0.1.0/24
        PersistentKeepalive = 25" \
          >"$name/wg0.conf"
        echo $pubKey >"$name/$name-split.pub"

        key=$(${wg} genkey)
        pubKey=$(echo $key | ${wg} pubkey)

        echo "[Interface]
        PrivateKey = $key
        Address = 10.0.254.$addr/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = $serverPubkey
        Endpoint = $serverIP:51820
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25" \
          >"$name/wg1.conf"
        echo $pubKey >"$name/$name-full.pub"

        echo Done
      '';
  # TODO: this would be nice to have on wayland as well
  # See:
  # - https://github.com/bugaevc/wl-clipboard
  # - https://gitlab.freedesktop.org/emersion/grim
  # - https://github.com/emersion/slurp
  dmenu-screenshot =
    pkgs.writeScriptBin "dmenu-screenshot"
      # sh
      ''
        #!/bin/sh
        set -euxo pipefail

        sel="Selection"
        full="Fullscreen"
        win="Window"
        # TODO: Add option to screenshot one monitor
        # TODO: Color picker?

        screenshot() {
          read mode

          local save_path="$HOME/Pictures/Screenshots"
          mkdir -p "$save_path"

          local name="$(date +%Y-%m-%d\ %H:%M:%S).png"
          local path="$save_path/$name"

          local temp=$(mktemp /tmp/screenshot.XXXXXXX.png)

          case "$mode" in
          $sel)
            ${maim} -u -s "$temp"
            ;;

          $full)
            ${maim} -t 1 "$temp"
            ;;

          $win)
            ${maim} -u -i $(${xdotool} getactivewindow) "$temp"
            ;;
          esac

          cp "$temp" "$path"
          cat "$temp" | ${copyCmd}
        }

        selection=$(echo -e "$sel\n$full\n$win" | ${dmenu})
        echo "$selection" |
          screenshot
      '';
}
