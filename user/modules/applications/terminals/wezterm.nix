{ extraConfig, ... }:
{
  programs.wezterm = {
    enable = true;
    extraConfig =
      "local font_name = \"${(import ../../fonts/names.nix).mono}\"\n"
      + "local color_scheme = \"Catppuccin ${extraConfig.catppuccinColors.upper.flavor}\"\n"
      +
        # lua
        ''
          local config = wezterm.config_builder()

          config.font = wezterm.font(font_name)
          config.font_size = 18
          config.color_scheme = color_scheme
          config.use_fancy_tab_bar = false
          config.tab_bar_at_bottom = true

          -- https://github.com/wez/wezterm/issues/5990
          config.front_end = "WebGpu"

          config.audible_bell = "Disabled"

          config.ssh_domains = wezterm.default_ssh_domains()
          for _, dom in ipairs(config.ssh_domains) do
          	dom.assume_shell = "Posix"
          end

          config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }
          local act = wezterm.action
          config.keys = {
          	-- Tabs
          	{
          		key = "t",
          		mods = "LEADER",
          		action = act.SpawnTab("CurrentPaneDomain"),
          	},

          	-- Splits
          	{
          		key = "v",
          		mods = "LEADER|SHIFT",
          		action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
          	},
          	{
          		key = "h",
          		mods = "LEADER|SHIFT",
          		action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
          	},

          	-- Pane movement
          	{
          		key = "h",
          		mods = "LEADER",
          		action = act.ActivatePaneDirection("Left"),
          	},
          	{
          		key = "l",
          		mods = "LEADER",
          		action = act.ActivatePaneDirection("Right"),
          	},
          	{
          		key = "j",
          		mods = "LEADER",
          		action = act.ActivatePaneDirection("Up"),
          	},
          	{
          		key = "k",
          		mods = "LEADER",
          		action = act.ActivatePaneDirection("Down"),
          	},

          	-- Send "CTRL-A" to the terminal when pressing CTRL-A, CTRL-A
          	{
          		key = "a",
          		mods = "LEADER|CTRL",
          		action = act.SendKey({ key = "a", mods = "CTRL" }),
          	},
          }

          return config
        '';
  };
}
