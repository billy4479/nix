{ extraConfig, ... }:
{
  catppuccin.kitty.enable = true;
  programs.kitty = {
    enable = true;
    font = {
      name = (import ../../fonts/names.nix).mono;

      # turns out this is the perfect size to fit 100 vim columns
      # on 2/3 of the screen of portatiolo
      size = 15;
    };
    shellIntegration.enableZshIntegration = true;
    settings = {
      copy_on_select = false;
      enable_audio_bell = false;
      window_padding_width = 0;
      confirm_os_window_close = 0;
      # background_opacity = 1;
      background_opacity = if extraConfig.desktop == "kde" then "1" else "0.85";
      shell = "zsh";
      update_check_interval = 0;

      clear_all_shortcuts = true;

      active_tab_background = "#a6d189";
      tab_bar_style = "powerline";
    };
    keybindings =
      let
        leader = "ctrl+a>";
      in
      {
        "ctrl+equal" = "change_font_size all +1.0";
        "ctrl+minus" = "change_font_size all -1.0";
        "ctrl+0" = "change_font_size all 0";

        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";

        "${leader}t" = "launch --cwd=current --type=tab";
        "${leader}n" = "next_tab";
        "${leader}p" = "previous_tab";
        "${leader}+r" = "set_tab_title";

        "${leader}l" = "next_layout";
        "${leader}shift+t" = "launch --cwd=current";
      };
  };
}
