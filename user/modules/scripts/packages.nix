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
        nix build .#nixosConfigurations.$1.config.system.build.toplevel --print-out-paths -o ${outPath} -Lv &&
          nix store sign --key-file ${config.sops.secrets.nix-signing-key.path} --recursive ${outPath} -Lv &&
          nix copy --to ssh://$1 ${outPath} -Lv
      '';

  flatten =
    pkgs.writeScriptBin "flatten"
      # sh
      ''
        #!/usr/bin/env bash
        set -euo pipefail

        usage() {
            cat <<'EOF'
        Usage: flatten [-v] PATH

        Options:
          -v    Verbose extraction when PATH is an archive

        Behavior:
          - If PATH is a directory, flatten its files into PATH_flattened
          - If PATH is an archive, extract it with 7z into a temp directory, then flatten
          - Archive extraction is not recursive
          - Directory structure is not preserved
          - Filename conflicts are resolved by appending _N before the extension
        EOF
        }

        verbose=0

        while getopts ":v" opt; do
            case "$opt" in
                v) verbose=1 ;;
                *) usage; exit 1 ;;
            esac
        done
        shift $((OPTIND - 1))

        if [[ $# -ne 1 ]]; then
            usage
            exit 1
        fi

        input_path=$1

        if [[ ! -e "$input_path" ]]; then
            echo "Error: path does not exist: $input_path" >&2
            exit 1
        fi

        if ! command -v 7z >/dev/null 2>&1; then
            echo "Error: 7z is required but not installed or not in PATH." >&2
            exit 1
        fi

        cleanup() {
            if [[ -n "${"tmpdir:-"}" && -d "${"tmpdir:-"}" ]]; then
                rm -rf -- "$tmpdir"
            fi
        }
        trap cleanup EXIT

        is_archive() {
            local path=$1
            # Test archive integrity/listability with 7z.
            # Treat it as an archive only if 7z can recognize it.
            7z l -ba -- "$path" >/dev/null 2>&1
        }

        resolve_conflict() {
            local dest_dir=$1
            local filename=$2
            local base ext candidate n

            if [[ "$filename" == *.* && "$filename" != .* ]]; then
                base=''${filename%.*}
                ext=.''${filename##*.}
            else
                base=$filename
                ext=
            fi

            candidate="$dest_dir/$filename"
            n=1
            while [[ -e "$candidate" ]]; do
                candidate="$dest_dir/''${base}_$n$ext"
                n=$((n + 1))
            done

            printf '%s\n' "$candidate"
        }

        flatten_from_dir() {
            local src_dir=$1
            local out_dir=$2

            # Find all regular files under src_dir, excluding anything already inside out_dir.
            find "$src_dir" -type f ! -path "$out_dir/*" -print0 |
            while IFS= read -r -d "" file; do
                local name target
                name=$(basename "$file")
                target=$(resolve_conflict "$out_dir" "$name")
                mv -- "$file" "$target"
            done
        }

        source_dir=""
        output_dir="''${input_path}_flattened"

        if [[ -e "$output_dir" ]]; then
            echo "Error: destination already exists: $output_dir" >&2
            exit 1
        fi

        mkdir -p -- "$output_dir"

        if [[ -d "$input_path" ]]; then
            source_dir=$input_path
            flatten_from_dir "$source_dir" "$output_dir"
        elif is_archive "$input_path"; then
            tmpdir=$(mktemp -d)
            if [[ $verbose -eq 1 ]]; then
                7z x -bb1 -o"$tmpdir" -- "$input_path"
            else
                7z x -bd -bso0 -bsp0 -o"$tmpdir" -- "$input_path" >/dev/null
            fi
            source_dir=$tmpdir
            flatten_from_dir "$source_dir" "$output_dir"
        else
            echo "Error: input is neither a directory nor a recognized archive: $input_path" >&2
            exit 1
        fi
      '';
}
