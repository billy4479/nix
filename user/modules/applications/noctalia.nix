{
  pkgs,
  flakeInputs,
  config,
  ...
}:
{
  imports = [
    flakeInputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    package = flakeInputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

    settings = {
      shell = {
        font_family = "sans-serif";
        time_format = "{:%H:%M}";
        date_format = "%A, %x";
        telemetry_enabled = false;
        settings_show_advanced = true;
        clipboard_enabled = true;
        clipboard_history_max_entries = 100;
        clipboard_auto_paste = "auto";

        animation = {
          enabled = true;
          speed = 1.0;
        };

        card_borders = false;

        shadow = {
          direction = "down_right";
          alpha = 0.55;
        };

        panel = {
          transparency_mode = "solid";
          borders = false;
          shadow = true;
          launcher_placement = "floating";
          launcher_position = "center";
          clipboard_position = "center";
          control_center_placement = "attached";
          open_near_click_control_center = true;
          session_placement = "floating";
          session_position = "center";
        };

        screen_corners.enabled = false;

        launcher = {
          layout = "full";
          width = 760;
          search_position = "top";
          default_view = "all";
          categories = true;
          show_settings_button = true;
          show_session_button = true;
          show_icons = true;
          compact = false;
          app_grid = false;
          track_usage = true;
          sort_by_usage = true;
          ignore_mouse = false;
          pinned = [ ];
          provider_prefix = "/";
          auto_paste = "auto";

          providers = {
            session.global = true;
            windows.global = true;
          };
        };

        mpris.blacklist = [ ];

        session = {
          show_shortcuts = true;
          grid = false;
          actions = [
            {
              action = "lock";
              shortcut = "1";
            }
            {
              action = "suspend";
              shortcut = "2";
              countdown_seconds = 10;
            }
            {
              action = "command";
              label = "Hibernate";
              glyph = "bedtime";
              command = "systemctl hibernate";
              shortcut = "3";
              countdown_seconds = 10;
            }
            {
              action = "reboot";
              shortcut = "4";
              countdown_seconds = 10;
            }
            {
              action = "logout";
              shortcut = "5";
            }
            {
              action = "shutdown";
              shortcut = "6";
              countdown_seconds = 10;
            }
            {
              action = "reboot_uefi";
              shortcut = "7";
              countdown_seconds = 10;
            }
          ];
        };
      };

      bar = {
        order = [ "main" ];

        main = {
          position = "top";
          thickness = 31;
          background_opacity = 0.93;
          radius = 0;
          margin_ends = 0;
          padding = 5;
          concave_edge_corners = false;
          capsule = true;
          capsule_thickness = 0.82;
          border_width = 0.0;
          widget_spacing = 6;
          shadow = true;
          reserve_space = true;
          auto_hide = false;

          start = [ "workspaces" ];
          center = [
            "active_window"
            "media"
          ];
          end = [
            "group:sysmon"
            "tray"
            "notifications"
            "battery"
            "volume"
            "clock"
          ];

          capsule_group = [
            {
              id = "sysmon";
              members = [
                "cpu"
                "temp"
                "mem"
                "net_rx"
                "net_tx"
              ];
            }
          ];
        };
      };

      widget = {
        workspaces.labels_only_when_occupied = true;

        active_window = {
          max_length = 145;
          title_scroll = "on_hover";
        };

        media = {
          max_length = 145;
          artist_first = true;
          title_scroll = "on_hover";
          hide_when_no_media = true;
          hide_when_idle = false;
        };

        cpu = {
          type = "sysmon";
          stat = "cpu_usage";
          visualization = "gauge";
          show_value = false;
        };

        temp = {
          type = "sysmon";
          stat = "cpu_temp";
          visualization = "gauge";
          show_value = false;
        };

        mem = {
          type = "sysmon";
          stat = "ram_used";
          visualization = "gauge";
          show_value = false;
        };

        net_rx = {
          type = "sysmon";
          stat = "net_rx";
          visualization = "none";
        };

        net_tx = {
          type = "sysmon";
          stat = "net_tx";
          visualization = "none";
        };

        battery = {
          display_mode = "graphic";
          show_label = false;
        };

        volume.show_label = false;

        tray = {
          drawer = true;
          hide_passive = false;
        };

        clock.format = "{:%H:%M %a, %b %d}";
      };

      theme = {
        mode = "dark";
        source = "custom";
        custom_palette = "CatppuccinMacchiato";
      };

      wallpaper = {
        enabled = true;
        fill_mode = "crop";
        fill_color = "#000000";
        transition = [
          "fade"
          "wipe"
          "disc"
          "stripes"
          "zoom"
          "honeycomb"
          "vortex"
          "pixel"
          "diamond"
          "golden"
          "melt"
        ];
        transition_duration = 1500;
        edge_smoothness = 0.05;
        transition_on_startup = true;
        directory = "${config.xdg.userDirs.pictures}/wallpapers";

        automation = {
          enabled = false;
          interval_seconds = 300;
          order = "random";
        };
      };

      backdrop = {
        enabled = false;
        blur_intensity = 0.4;
        tint_intensity = 0.6;
      };

      notification = {
        position = "top_right";
        layer = "overlay";
        background_opacity = 1.0;
        keep_dismissed_in_history = false;
      };

      osd = {
        position = "top_right";
        hide_delay_ms = 2000;
        background_opacity = 1.0;

        kinds = {
          volume = true;
          volume_output = true;
          volume_input = true;
          brightness = true;
          wifi = false;
          bluetooth = false;
          power_profile = false;
          caffeine = false;
          nightlight = false;
          dnd = false;
          lock_keys = false;
          keyboard_layout = true;
          keyboard_backlight = false;
          media = false;
          privacy = false;
        };
      };

      lockscreen = {
        enabled = true;
        lock_before_suspend = true;
        fingerprint = false;
        transition = [ ];
        blur_intensity = 0.0;
        tint_intensity = 0.0;
      };

      keybinds = {
        validate = [
          "return"
          "kp_enter"
        ];
        cancel = [ "escape" ];
        left = [ "left" ];
        right = [ "right" ];
        up = [ "up" ];
        down = [ "down" ];
        delete = [ "del" ];
      };

      audio = {
        enable_overdrive = false;
        enable_sounds = false;
        sound_volume = 0.5;
      };

      brightness = {
        enable_ddcutil = false;
        minimum_brightness = 0.01;
      };

      battery.warning_threshold = 20;

      nightlight = {
        enabled = false;
        force = false;
        temperature_day = 6500;
        temperature_night = 4000;
      };

      location.address = "Milan";

      weather = {
        enabled = true;
        refresh_minutes = 30;
        unit = "metric";
        effects = true;
      };

      calendar.enabled = true;

      system.monitor = {
        enabled = true;
        cpu_usage_activity_threshold = 80;
        cpu_usage_critical_threshold = 90;
        cpu_temp_activity_threshold = 80;
        cpu_temp_critical_threshold = 90;
        gpu_temp_activity_threshold = 80;
        gpu_temp_critical_threshold = 90;
        gpu_usage_activity_threshold = 80;
        gpu_usage_critical_threshold = 90;
        ram_pct_activity_threshold = 80;
        ram_pct_critical_threshold = 90;
        swap_pct_activity_threshold = 80;
        swap_pct_critical_threshold = 90;
        disk_used_pct_activity_threshold = 80;
        disk_used_pct_critical_threshold = 90;
        disk_free_pct_activity_threshold = 20;
        disk_free_pct_critical_threshold = 10;
      };

      control_center = {
        calendar = {
          show_events_card = true;
          show_week_numbers = false;
        };

        shortcuts = [
          { type = "wifi"; }
          { type = "bluetooth"; }
          { type = "notification"; }
          { type = "power_profile"; }
          { type = "caffeine"; }
          { type = "nightlight"; }
        ];
      };

      dock.enabled = false;

      plugins.auto_update = "none";
    };

    # v5 rejects a custom palette without a `terminal` section and falls back to
    # the builtin palette, so the ANSI colors are required even though the shell
    # does not use them (no templates enabled). Values are the official
    # Catppuccin Macchiato terminal palette.
    customPalettes.CatppuccinMacchiato = {
      dark = {
        mError = "#e78284";
        mOnError = "#232634";
        mOnPrimary = "#232634";
        mOnSecondary = "#232634";
        mOnSurface = "#c6d0f5";
        mOnSurfaceVariant = "#a5adce";
        mOnTertiary = "#232634";
        mOnHover = "#232634";
        mOutline = "#292c3c";
        mPrimary = "#a6da95";
        mSecondary = "#b5bfe2";
        mShadow = "#232634";
        mSurface = "#24273a";
        mHover = "#626880";
        mSurfaceVariant = "#414559";
        mTertiary = "#e5c890";

        terminal = {
          normal = {
            black = "#494d64"; # surface 1
            red = "#ed8796";
            green = "#a6da95";
            yellow = "#eed49f";
            blue = "#8aadf4";
            magenta = "#f5bde6";
            cyan = "#8bd5ca";
            white = "#a5adcb"; # subtext 0
          };
          bright = {
            black = "#5b6078"; # surface 2
            red = "#ec7486";
            green = "#8ccf7f";
            yellow = "#e1c682";
            blue = "#78a1f6";
            magenta = "#f2a9dd";
            cyan = "#63cbc0";
            white = "#b8c0e0"; # subtext 1
          };
          foreground = "#cad3f5"; # text
          background = "#24273a"; # base
          cursor = "#f4dbd6"; # rosewater
          cursorText = "#24273a"; # base
          selectionFg = "#cad3f5"; # text
          selectionBg = "#5b6078"; # surface 2
        };
      };
    };
  };
}
