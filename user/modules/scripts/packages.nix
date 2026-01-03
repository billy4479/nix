{
  pkgs,
  lib,
  config,
  extraConfig,
  ...
}:
let
  home = config.home.homeDirectory;
  dmenu = "${lib.getExe pkgs.rofi} -i -dmenu";

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
        set -eo pipefail

        usage() {
          echo "Usage: $0 -k <serverPubkey> -a <addr> -n <name> [-o <outputFolder>]"
          exit 1
        }

        while getopts "k:a:n:h:o:" opt; do
          case "$opt" in
          k)
            serverPubkeyFile="$OPTARG"
            ;;
          a)
            addr="$OPTARG"
            ;;
          n)
            name="$OPTARG"
            ;;
          h)
            knownHostsFile="$OPTARG"
            ;;
          o)
            outputFolder="$OPTARG"
            ;;
          \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
          :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
          esac
        done

        shift $((OPTIND - 1))

        if [ -z "$serverPubkeyFile" ] || [ -z "$addr" ] || [ -z "$name" ]; then
          echo "All arguments are required." >&2
          usage
        fi

        serverPublicIP=$(cat "${config.sops.secrets.serveronePublicIP.path}")
        serverLocalIP="192.168.2.21"
        dns="1.1.1.1"
        serverPubkey=$(cat "$serverPubkeyFile")

        if [ ! -z "$outputFolder" ]; then
          mkdir -p "$outputFolder"
          pushd "$outputFolder"
        fi

        genConfig() {
          split="$1"
          local="$2"

          if [ "$split" = true ]; then
            # Respectively: server, containers, other clients
            allowedIPs="10.0.0.1/32, 10.0.1.0/24, 10.0.248.0/21"
            if [ "$local" = true ]; then
              address="10.0.251.$addr/32"
              confName="wg0.split.loc.conf"
              keyName="wg0-split-loc.pub"
              serverIP="$serverLocalIP"
            else
              address="10.0.252.$addr/32"
              confName="wg1.split.pub.conf"
              keyName="wg1-split-pub.pub"
              serverIP="$serverPublicIP"
            fi
          else
            allowedIPs="0.0.0.0/0, ::/0"
            if [ "$local" = true ]; then
              address="10.0.253.$addr/32"
              confName="wg2.full.loc.conf"
              keyName="wg2-full-loc.pub"
              serverIP="$serverLocalIP"
            else
              address="10.0.254.$addr/32"
              confName="wg3.full.pub.conf"
              keyName="wg3-full-pub.pub"
              serverIP="$serverPublicIP"
            fi
          fi

          echo "Generating $confName"

          key=$(${wg} genkey)
          pubKey=$(echo "$key" | ${wg} pubkey)

          echo "[Interface]
        PrivateKey = $key
        Address = $address
        DNS = $dns

        [Peer]
        PublicKey = $serverPubkey
        Endpoint = $serverIP:51820
        AllowedIPs = $allowedIPs
        PersistentKeepalive = 25 " \
          > "$confName"
          echo "$pubKey" > "$keyName"
        }

        genConfig true true
        genConfig true false
        genConfig false true
        genConfig false false

        if [ ! -z "$outputFolder" ]; then
          popd
        fi

        cat <<EOF

        Done, add to network-manager with
        nmcli connection import type wireguard file <config-file>.conf
        EOF
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

  clip-copy = pkgs.writeScriptBin "clip-copy" (
    if extraConfig.wayland then
      #sh
      ''
        #!/bin/sh
        exec ${pkgs.wl-clipboard}/bin/wl-copy --type text/plain
      ''
    else
      #sh
      ''
        #!/bin/sh
        exec ${lib.getExe pkgs.xclip} -selection clipboard
      ''
  );

  clip-paste = pkgs.writeScriptBin "clip-paste" (
    if extraConfig.wayland then
      #sh
      ''
        #!/bin/sh
        exec ${pkgs.wl-clipboard}/bin/wl-paste --no-newline
      ''
    else
      #sh
      ''
        #!/bin/sh
        exec ${lib.getExe pkgs.xclip} -selection clipboard -o
      ''
  );
}
