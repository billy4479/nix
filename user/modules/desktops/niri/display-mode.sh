# This script is wrapped with writeShellApplication (bash, errexit, nounset, pipefail).
mode=$(printf '%s\n' 'Laptop only' 'External only' 'Extend' 'Duplicate' |
  rofi -dmenu -i -no-custom -p 'Display mode') || exit 0
case "$mode" in
'Laptop only' | 'External only' | 'Extend' | 'Duplicate') ;;
*) exit 0 ;;
esac

outputs=$(niri msg --json outputs)
laptop=$(jq -r '[keys[] | select(test("^(eDP|LVDS|DSI)-"))][0] // empty' <<<"$outputs")
if [[ -z "$laptop" ]]; then
  rofi -e 'No laptop display found.'
  exit 1
fi
mapfile -t external < <(jq -r --arg laptop "$laptop" 'keys[] | select(. != $laptop)' <<<"$outputs")

target=''
if [[ "$mode" != 'Laptop only' ]]; then
  if ((${#external[@]} == 0)); then
    rofi -e 'No external display connected.'
    exit 1
  fi
  if [[ "$mode" != 'Extend' ]]; then
    target=${external[0]}
    if ((${#external[@]} > 1)); then
      target=$(printf '%s\n' "${external[@]}" |
        rofi -dmenu -i -no-custom -p 'External display') || exit 0
      # Validate the selection before changing any outputs.
      jq -e --arg target "$target" --arg laptop "$laptop" \
        'has($target) and ($target != $laptop)' <<<"$outputs" >/dev/null || exit 0
    fi
  fi
fi

# Stop only the mirror owned by this menu, not unrelated wl-mirror instances.
if systemctl --user --quiet is-active niri-display-mirror.service; then
  systemctl --user stop niri-display-mirror.service
fi

# Enable the destination before disabling other outputs.
case "$mode" in
'Laptop only')
  niri msg output "$laptop" on
  for output in "${external[@]}"; do
    niri msg output "$output" off
  done
  ;;
'External only')
  niri msg output "$target" on
  niri msg output "$laptop" off
  for output in "${external[@]}"; do
    if [[ "$output" != "$target" ]]; then
      niri msg output "$output" off
    fi
  done
  ;;
'Extend' | 'Duplicate')
  niri msg output "$laptop" on
  for output in "${external[@]}"; do
    niri msg output "$output" on
  done
  if [[ "$mode" == 'Duplicate' ]]; then
    systemd-run --user --collect --unit=niri-display-mirror \
      --setenv="WAYLAND_DISPLAY=$WAYLAND_DISPLAY" \
      "$(command -v wl-mirror)" --title=niri-display-mirror --fullscreen-output "$target" "$laptop"
    niri msg action focus-monitor "$laptop"
  fi
  ;;
esac
