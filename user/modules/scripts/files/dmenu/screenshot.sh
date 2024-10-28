#!/bin/sh

set -euxo pipefail

sel="Selection"
full="Fullscreen"
win="Window"

screenshot() {
	read mode

	local save_path="$HOME/Pictures/Screenshots"
	mkdir -p "$save_path"

	local name="$(date +%Y-%m-%d\ %H:%M:%S).png"
	local path="$save_path/$name"

	local temp=$(mktemp /tmp/screenshot.XXXXXXX.png)

	case "$mode" in
	$sel)
		maim -u -s "$temp"
		;;

	$full)
		maim -t 1 "$temp"
		;;

	$win)
		maim -u -i $(xdotool getactivewindow) "$temp"
		;;
	esac

	cp "$temp" "$path"
	cat "$temp" | xclip -selection clipboard -t image/png
}

echo -e "$sel\n$full\n$win" | rofi -dmenu | screenshot
