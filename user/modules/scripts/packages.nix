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

  activate-system =
    pkgs.writeScriptBin "activate-system"
      # sh
      ''
        sudo nix-env -p /nix/var/nix/profiles/system --set "$1" && sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
      '';

  build-host-and-copy =
    let
      outPath = "/tmp/nix-system";
    in
    pkgs.writeScriptBin "build-host-and-copy"
      # sh
      ''
        rm -f ${outPath}
        nix build .#nixosConfigurations.$1.config.system.build.toplevel --print-out-paths -o ${outPath} && nix copy --to ssh://$1 ${outPath}
      '';
}
