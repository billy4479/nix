#!/bin/sh

set -euo pipefail

fd --extension=pdf -I . "$HOME/Downloads" "$HOME/code" | rofi -dmenu | xargs --delimiter='\n' xdg-open
