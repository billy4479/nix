# Noctalia Greeter

## Configuration

Both Niri hosts use greetd with Noctalia Greeter instead of SDDM. The pinned
Nixpkgs provides the package (1.7.0) and NixOS module, so no additional flake input
is needed. KDE and Qtile configurations still select SDDM.

- `system/modules/desktops/default.nix` selects the login manager by desktop.
- `system/modules/noctalia-greeter.nix` configures the greeter's default Niri
  session, US international and Italian keyboard layouts, Num Lock, and display
  blanking after five minutes without input.
- `system/modules/autologin.nix` preserves laptop autologin through greetd's
  `initial_session`, launching `niri-session` for systemd session startup. Other
  desktops retain the generic display-manager autologin settings.

The native module enables greetd, AccountsService and Polkit, creates the
state directory, and launches the bundled session wrapper. No separate Cage,
Niri, or Hyprland greeter compositor is needed: the greeter has its own wlroots
compositor. It does not replace Niri or the Noctalia lock screen.

Removing the SDDM import also removes this repository's forced Xorg enablement.
Xorg is disabled on both Niri hosts, but the NVIDIA driver configuration under
`services.xserver.videoDrivers` remains necessary and is unchanged.

### Host behavior

**computerone:** shows the login screen at boot. The greeter explicitly matches
Niri's monitor layout: `DP-2` on the left, rotated 90 degrees when
`extraConfig.rotateMonitor` is enabled, and `DP-1` on the right. Both use scale
1; requested refresh rates are 170 Hz and 75 Hz respectively. The greeter uses
the EDID-preferred resolution and matches fractional refresh rates within 1 Hz.
Its display settings are separate from the Home Manager Niri configuration;
keep both configurations aligned when changing monitors.

**portatilo:** automatically logs `billy` into Niri at boot and shows the greeter
after logout. To require login at every boot, remove the autologin module import
from `system/hosts/portatilo/default.nix`. Greeter output selection, scaling and
lid handling use upstream defaults.

## Optional appearance sync

Open **Noctalia Settings → Security → Noctalia Greeter → Sync Now**, authorize
it, and log out to see the result. Sync can copy wallpaper, palette, font,
monitor layout, rotation and scale. Fonts must be available system-wide, not
only in the user's home directory.

Administrator authorization remains required by default. To allow automatic
appearance sync without repeated prompts, explicitly opt in with:

```nix
services.displayManager.noctalia-greeter.passwordlessSyncUsers = [ "billy" ];
```

This authorizes only the constrained appearance-sync helper for an active local
user. The pinned Noctalia shell (5.4.1) and greeter meet the documented version
requirements. Appearance sync has not been runtime-tested.

Declarative values in `greeter.toml` take precedence over synced values in
`sync.toml`. In particular, the desktop's explicit output layout, scale,
rotation and refresh rates remain authoritative after sync.

Use Nixpkgs module options, not similarly named upstream flake options. Nixpkgs
uses `passwordlessSyncUsers` and `extraArgs`; the upstream module instead uses
`passwordless-sync-users` and `greeter-args`.

## Validation and rollout

Both complete system derivations evaluate successfully. Evaluation confirms:

- SDDM and Xorg are disabled, greetd is enabled, and `niri` is available.
- Only the laptop has a greetd initial autologin session.
- The desktop has its rotated monitor layout and refresh rates configured.
- Passwordless appearance sync remains disabled on both hosts.

The greeter package and both generated greetd service units build successfully.
A combined full-system build was attempted but exceeded the 20-minute command
limit while building dependencies, without a greeter-specific error reported.
Full-system build completion and runtime behavior are not yet verified.

Before deployment, complete the builds:

```sh
nix build .#nixosConfigurations.portatilo.config.system.build.toplevel
nix build .#nixosConfigurations.computerone.config.system.build.toplevel
```

Deployment is the user's responsibility. Prefer staging the new generation for
the next boot over replacing a running display manager mid-session. Keep the
previous boot generation available and ensure TTY or SSH recovery access.

After deployment, check password login, failed-password retry, logout and login
again, reboot, suspend/resume, keyboard layouts, and any keyring unlock behavior
in use. On the laptop, verify initial autologin, the greeter after logout,
scaling, external displays, and closed-lid behavior. On the desktop, verify
actual rendering with the proprietary NVIDIA driver and both monitor
orientations. Niri working does not prove this separate wlroots compositor
works on the same driver.

Inspect failures with `journalctl -u greetd -b`. Restore the previous boot
generation if graphical login fails.

## Sources

- [Installation](https://docs.noctalia.dev/greeter/installation/)
- [Display configuration](https://docs.noctalia.dev/greeter/displays/)
- [Appearance sync](https://docs.noctalia.dev/greeter/sync/)
- [Troubleshooting](https://docs.noctalia.dev/greeter/troubleshooting/)
- [Upstream source and flake](https://github.com/noctalia-dev/noctalia-greeter)
- Pinned Nixpkgs: `nixos/modules/services/display-managers/noctalia-greeter.nix`
  and `greetd.nix`.
