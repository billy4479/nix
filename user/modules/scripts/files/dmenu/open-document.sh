#!/bin/sh

set -euo pipefail

files=$(fd --extension=pdf -I . "$HOME/Downloads" "$HOME/code")
files=$(echo "$files" | sed "s,$HOME/,,g")
echo "$files" | rofi -dmenu | xargs --delimiter '\n' printf "$HOME/%s" | xargs xdg-open
