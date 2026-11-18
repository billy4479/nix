# Laptop display modes

## Stay awake

**Mod+Shift+I** or the coffee-mug button in the bar toggles stay-awake mode on
`portatilo`, with a desktop notification. While active:

- swayidle skips its idle-suspend timeout, so the laptop keeps running unattended;
- closing the lid does not suspend, because `stay-awake.service` holds a
  `handle-lid-switch` inhibitor with logind;
- niri still turns off the internal panel when the lid closes, and external
  displays keep working.

Idle dimming, screen-off/locking and their timeouts are unchanged, and explicit
locking or suspending still works. The mode is per login: it starts off after
logout or reboot.

Implementation: the `stay-awake` script in `user/modules/scripts/packages.nix`
starts and stops the `stay-awake` user unit defined in
`user/modules/desktops/niri/default.nix`. The swayidle suspend command checks the
unit state before suspending, and the polkit rule in
`system/hosts/portatilo/default.nix` lets the user unit hold the lid-switch
inhibitor. Check or change it from a terminal with:

```sh
stay-awake status
stay-awake on
stay-awake off
```

## Display selection

On `portatilo`, **Mod+Shift+P** opens a display-mode menu:

- **Laptop only** enables the internal panel and disables connected external outputs.
- **External only** enables the chosen external output and disables the other outputs.
- **Extend** enables all connected outputs, using niri's existing layout and scaling.
- **Duplicate** enables the outputs and opens a fullscreen `wl-mirror` of the laptop
  panel on the chosen external monitor. Focus returns to the laptop.

When multiple external monitors are connected, External only and Duplicate ask
which one to use. Duplicate leaves the other monitors extended. Cancelling either
menu leaves the current setup unchanged. Selecting another mode stops the mirror
started by this menu, without affecting other `wl-mirror` instances.

Connectors are detected through `niri msg --json outputs`, including disabled
outputs. The internal panel is identified by an `eDP-`, `LVDS-`, or `DSI-` connector.
The three native modes use only niri output commands. Duplicate uses a transient
user service, `niri-display-mirror.service`, so the mirror survives the menu closing
and can be stopped independently:

```sh
systemctl --user stop niri-display-mirror.service
journalctl --user -u niri-display-mirror.service
```

This is capture-based mirroring, not native display cloning: latency and
letterboxing are possible. The mirror is a normal fullscreen window, so switching
workspaces on the external monitor can hide it. If the external monitor is
unplugged during Duplicate, switch to Laptop only to stop mirroring.

Mode changes are temporary and do not change the default hotplug behavior. The
configuration lives in `user/modules/desktops/niri/display-mode.{nix,sh}`.
`Mod+P` retains its existing previous-workspace action on all machines.

Run the transition tests with:

```sh
python3 tests/display-mode.py
```
