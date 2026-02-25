{
  pkgs,
  lib,
  extraConfig,
  flakeInputs,
  ...
}@args:
let
  scripts = import ../../scripts/packages.nix args;
  noctaliaIpc =
    x:
    [
      "noctalia-shell"
      "ipc"
      "call"
    ]
    ++ (lib.strings.splitString " " x);
in
{
  imports = [
    flakeInputs.niri.homeModules.niri
    ../../applications/noctalia.nix

    ../../applications/rofi.nix
    # ../../applications/pcmanfm.nix
    ../../applications/nemo.nix
    # ../../services/dunst.nix
    ../../services/gammastep.nix
    ../../services/kdeconnect.nix
    ../../services/lxqt-policykit.nix
    ../../services/nm-applet.nix
    ../../services/playerctld.nix
    ../../services/udiskie.nix
  ];

  programs.niri = {
    enable = true;
    package = pkgs.niri;

    settings = {
      prefer-no-csd = true;
      binds = {
        "Mod+Shift+Slash".action.show-hotkey-overlay = { };

        "Mod+Return".action.spawn = "kitty";
        "Mod+Shift+Return".action.spawn = noctaliaIpc "launcher toggle";
        "Mod+Ctrl+Shift+Return".action.spawn = noctaliaIpc "launcher command";
        "Mod+Period".action.spawn = noctaliaIpc "launcher emoji";
        "Mod+V".action.spawn = noctaliaIpc "launcher clipboard";

        "Mod+B".action.spawn = "firefox";
        "Mod+C".action.spawn = lib.getExe pkgs.qalculate-gtk;
        "Mod+E".action.spawn = "nemo";
        "Mod+D".action.spawn = lib.getExe scripts.open-document;
        "Mod+Y".action.spawn = lib.getExe scripts.mpv-url;

        "Mod+L".action.spawn = noctaliaIpc "lockScreen lock";
        "Mod+Q".action.spawn = noctaliaIpc "sessionMenu toggle";

        # Volume
        "XF86AudioRaiseVolume" = {
          allow-when-locked = true;
          action.spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05+ -l 1.0";
        };

        "XF86AudioLowerVolume" = {
          allow-when-locked = true;
          action.spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.05-";
        };

        "XF86AudioMute" = {
          allow-when-locked = true;
          action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };

        "XF86AudioMicMute" = {
          allow-when-locked = true;
          action.spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
        };

        # Media
        "XF86AudioPlay".action.spawn = [
          "playerctl"
          "-p"
          "spotify,%any"
          "play-pause"
        ];
        "XF86AudioStop".action.spawn = [
          "playerctl"
          "-p"
          "spotify,%any"
          "stop"
        ];
        "XF86AudioPrev".action.spawn = [
          "playerctl"
          "-p"
          "spotify,%any"
          "previous"
        ];
        "XF86AudioNext".action.spawn = [
          "playerctl"
          "-p"
          "spotify,%any"
          "next"
        ];

        # Brightness
        "XF86MonBrightnessUp" = {
          allow-when-locked = true;
          action.spawn = [
            "brightnessctl"
            "--class=backlight"
            "set"
            "+5%"
          ];
        };

        "XF86MonBrightnessDown" = {
          allow-when-locked = true;
          action.spawn = [
            "brightnessctl"
            "--class=backlight"
            "set"
            "5%-"
          ];
        };

        # Overview / window management
        "Mod+O" = {
          repeat = false;
          action.toggle-overview = { };
        };

        "Mod+Shift+C" = {
          repeat = false;
          action.close-window = { };
        };

        # Focus
        "Mod+J".action.focus-window-down-or-column-right = { };
        "Mod+K".action.focus-window-up-or-column-left = { };

        "Mod+WheelScrollUp".action.focus-window-up-or-column-left = { };
        "Mod+WheelScrollDown".action.focus-window-down-or-column-right = { };

        "Mod+Comma".action.focus-monitor-next = { };
        "Mod+Ctrl+Comma".action.move-window-to-monitor-next = { };

        # Move
        "Mod+Ctrl+H".action.move-column-left = { };
        "Mod+Ctrl+J".action.move-window-down = { };
        "Mod+Ctrl+K".action.move-window-up = { };
        "Mod+Ctrl+L".action.move-column-right = { };

        # Workspaces
        "Mod+Page_Up".action.focus-workspace-up = { };
        "Mod+Page_Down".action.focus-workspace-down = { };

        "Mod+Shift+WheelScrollUp".action.focus-workspace-up = { };
        "Mod+Shift+WheelScrollDown".action.focus-workspace-down = { };

        "Mod+N".action.focus-workspace-down = { };
        "Mod+P".action.focus-workspace-up = { };
        "Mod+Shift+J".action.focus-workspace-down = { };
        "Mod+Shift+K".action.focus-workspace-up = { };

        # Width-height adjustments
        "Mod+Minus".action.set-column-width = "-10%";
        "Mod+Equal".action.set-column-width = "+10%";

        "Mod+Shift+Minus".action.set-window-height = "-10%";
        "Mod+Shift+Equal".action.set-window-height = "+10%";

        # Floating
        "Mod+F".action.toggle-window-floating = { };
        # "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = { };

        # Layout tweaks
        "Mod+M".action.maximize-column = { };
        "Mod+Shift+M".action.fullscreen-window = { };
        # "Mod+M".action.maximize-window-to-edges = { };

        # "Mod+C".action.center-column = { };
        # "Mod+Ctrl+C".action.center-visible-columns = { };
        "Mod+Space".action.switch-preset-column-width = { };

        # Screenshots
        "Print".action.screenshot = { };
        "Ctrl+Print".action.screenshot-screen = { };
        "Ctrl+Shift+Print".action.screenshot-window = { };

        # Keyboard inhibitor escape
        "Mod+Escape" = {
          allow-inhibiting = false;
          action.toggle-keyboard-shortcuts-inhibit = { };
        };

        # Quit
        "Mod+Shift+Q".action.quit = { };
        "Ctrl+Alt+Delete".action.quit = { };
      };

      input = {
        keyboard = {
          numlock = true;
          xkb.layout = "us(intl),it";
        };

        touchpad = {
          click-method = "clickfinger";
          natural-scroll = true;
          scroll-method = "two-finger";
          tap = true;
          tap-button-map = "left-right-middle";
        };

        focus-follows-mouse.enable = true;
        warp-mouse-to-focus = {
          enable = true;
          mode = "center-xy";
        };
      };

      outputs =
        if extraConfig.hostname == "computerone" then
          {
            "DP-1" = {
              mode = {
                width = 2560;
                height = 1440;
                refresh = 169.831;
              };

              position = {
                x = if extraConfig.rotateMonitor then 1080 else 1920;
                y = 0;
              };
            };
            "DP-2" = {
              mode = {
                width = 1920;
                height = 1080;
                refresh = 74.986;
              };
              transform.rotation = if extraConfig.rotateMonitor then 90 else 0;
              position = {
                x = 0;
                y = 0;
              };
            };
          }
        else
          { };

      layout = {
        gaps = 8;
        focus-ring = {
          enable = true;
          width = 1;
          active.color = "#FFFFFF";
          inactive = null;
          urgent.color = "#FF0000";
        };

        shadow.enable = true;

        preset-column-widths = [
          { proportion = 1. / 3.; }
          { proportion = 1. / 2.; }
          { proportion = 2. / 3.; }
          { proportion = 1.; }
        ];

        preset-window-heights = [
          { proportion = 1. / 3.; }
          { proportion = 1. / 2.; }
          { proportion = 2. / 3.; }
          { proportion = 1.; }
        ];

      };

      environment = {
        QT_QPA_PLATFORM = "wayland";
        MOZ_ENABLE_WAYLAND = "1";
        NIXOS_OZONE_WL = "1";
      };

      xwayland-satellite = {
        enable = true;
        path = lib.getExe pkgs.xwayland-satellite;
      };

      screenshot-path = "~/Pictures/Screenshots/%Y-%m-%d_%H-%M-%S.png";

      window-rules = [
        {
          default-column-width = {
            proportion = 2. / 3.;
          };
        }
      ];
    };
  };
}
