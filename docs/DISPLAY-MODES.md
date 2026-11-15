# Laptop display modes

## Keep awake

**Mod+Shift+I** toggles Noctalia's caffeine mode, with on-screen feedback. While
active, it inhibits swayidle's automatic brightness dimming, screen-off/locking,
and idle suspension. Press it again to restore normal idle behavior. This binding
is available on both niri machines.

This prevents idle-triggered actions, not explicit locking/suspending or lid-close
actions. It does not change your configured brightness or timeout settings.

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
