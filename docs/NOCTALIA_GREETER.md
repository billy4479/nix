# Noctalia Greeter migration investigation

## Recommendation

Switching from SDDM to greetd with Noctalia Greeter is a good fit for the two
Niri hosts. Use the existing Nixpkgs package and NixOS module, not another flake
input. The pinned Nixpkgs already provides `noctalia-greeter` **1.7.0**, and the
pinned Noctalia shell is **5.4.1**.

This is an investigation only. No system or Home Manager configuration has been
changed, built, or deployed.

## Current setup

- `system/modules/desktops/default.nix` imports `system/modules/sddm.nix` for
  every desktop, including KDE and Qtile.
- The SDDM module enables its Wayland mode and forcibly enables Xorg.
- Both `computerone` and `portatilo` use Niri with Noctalia managed by standalone
  Home Manager. Their default system session is `niri`.
- `portatilo` imports `system/modules/autologin.nix`, enabling SDDM autologin for
  `billy`. `computerone` does not enable autologin.
- `computerone` uses the proprietary NVIDIA driver and two monitors, with
  `DP-2` rotated 90 degrees. `DP-1` runs at approximately 170 Hz and `DP-2` at
  75 Hz.
- The desktop keyboard configuration is US international plus Italian. The
  system graphical keyboard default is US international.

## Smallest migration

Add `system/modules/noctalia-greeter.nix` and select it instead of the SDDM
module for `desktop == "niri"`. Keep SDDM for the KDE and Qtile configurations
unless those are separately tested.

A starting configuration using the **pinned Nixpkgs module** is:

```nix
{ ... }:
{
  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      session.default = "niri";
      keyboard = {
        layout = "us,it";
        variant = "intl,";
        numlock = true;
      };
      idle.timeout = 300;
    };
  };
}
```

The module enables greetd, AccountsService and Polkit, creates the greeter state
directory, and launches the bundled session wrapper. No separate Cage, Niri, or
Hyprland greeter compositor is necessary: Noctalia Greeter has its own wlroots
compositor. It does not replace the desktop compositor or the Noctalia lock screen.

Removing the SDDM import also removes this repository's forced Xorg enablement.
An evaluation with the proposed replacement yields `services.xserver.enable =
false` on both hosts. Do not remove NVIDIA driver configuration merely because
it lives under `services.xserver.videoDrivers`.

### Laptop autologin

The pinned greetd module does **not** translate
`services.displayManager.autoLogin` into greetd configuration. To retain the
current behavior, replace the laptop's existing autologin import with:

```nix
{ config, extraConfig, ... }:
{
  services.greetd.settings.initial_session = {
    user = extraConfig.user.username;
    command = "${config.programs.niri.package}/bin/niri-session";
  };
}
```

Use `niri-session`, rather than bare `niri`, to retain Niri's systemd session
startup. With this configuration the login screen is skipped initially and
appears after logout. To see the greeter on every boot, remove autologin instead.
The existing `services.displayManager.defaultSession = "niri"` can remain, but
set the greeter's `settings.session.default` explicitly too.

### Appearance and monitors

Appearance sync is optional. Start with administrator-authorized **Sync Now**
from Noctalia's security settings, then log out to inspect the result. Sync can
copy wallpaper, palette, font, monitor layout, rotation, and scale. Greeter fonts
must be installed system-wide, not only in the user's home.

For automatic appearance sync without repeated authorization prompts, the
Nixpkgs module offers `passwordlessSyncUsers = [ "billy" ];`. This permits the
constrained appearance-only helper for an active local user; leave it unset
unless automatic sync is wanted. Noctalia and greeter versions in the current
pins exceed the documented version requirements, but sync was not runtime-tested.

For `computerone`, sync the display layout or explicitly configure
`settings.output.transforms`, `layout`, `scales`, and `refresh_rate`. The greeter
does not automatically read the Niri Home Manager configuration. By default it
shows the login UI on every connected monitor. On the laptop, verify scaling,
external displays, and closed-lid behavior.

The upstream flake module has different option spellings, including
`passwordless-sync-users` and `greeter-args`. Do not copy those into the Nixpkgs
module, which uses `passwordlessSyncUsers` and `extraArgs`.

## Validation and rollout

An evaluation-only overlay, held outside the repository, removed the SDDM module
and enabled the native Noctalia module on both hosts. It successfully evaluated
both complete system derivations, confirmed SDDM and Xorg were disabled, found
the `niri` session, and generated the laptop's greetd initial session.
This verifies module compatibility, not compilation or hardware behavior.

Before deploying an actual implementation:

1. Build both affected system configurations using the repository's normal
   `nix build .#nixosConfigurations.HOST.config.system.build.toplevel` command.
2. Have the user stage the new generation for the next boot, rather than
   replacing a running display manager mid-session. Keep the previous boot
   generation available and ensure TTY or SSH recovery access.
3. Check password login, failed-password retry, logout and login again, reboot,
   suspend/resume, keyboard layouts, and any keyring unlock behavior in use.
4. Test the NVIDIA desktop's actual greeter rendering and both monitor
   orientations. Niri working today does not prove this separate wlroots
   compositor works on the same driver.
5. On the laptop, check that initial autologin and the greeter after logout both
   work, or intentionally disable autologin.

Inspect failures with `journalctl -u greetd -b`. Restore the previous boot
generation if graphical login fails. Deployment remains the user's responsibility.

## Sources

- [Noctalia Greeter installation](https://docs.noctalia.dev/greeter/installation/)
- [Display configuration](https://docs.noctalia.dev/greeter/displays/)
- [Appearance sync](https://docs.noctalia.dev/greeter/sync/)
- [Troubleshooting](https://docs.noctalia.dev/greeter/troubleshooting/)
- [Upstream source and flake](https://github.com/noctalia-dev/noctalia-greeter)
- Pinned Nixpkgs: `nixos/modules/services/display-managers/noctalia-greeter.nix`
  and `greetd.nix`. These were used to verify the actual available options rather
  than assuming the latest website examples match the repository's pins.
