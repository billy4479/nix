#!/bin/sh
lxsession &
# picom & # Managed by nix
(sleep 1 && nitrogen --restore) &
# redshift & # Managed by nix
# nm-applet & # Manged by nix
xfce4-clipman &
# numlockx & # Managed by nix
# playerctld daemon & # Managed by nix
# dunst & # Managed by nix
# kdeconnect-indicator & # Managed by nix
# blueman-applet & # Managed by nix
# nut-monitor -H & # TODO: figure this out, right now I don't even use a UPS with this PC anymore