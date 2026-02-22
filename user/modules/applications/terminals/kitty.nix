{ ... }:
{
  catppuccin.kitty.enable = true;
  programs.kitty = {
    enable = true;
    font = {
      name = (import ../../fonts/names.nix).mono;
      size = 16;
    };
    shellIntegration.enableZshIntegration = true;
    settings = {
      copy_on_select = false;
      enable_audio_bell = false;
      window_padding_width = 0;
      confirm_os_window_close = 0;
      background_opacity = 1;
      # background_opacity = if extraConfig.desktop == "kde" then "1" else "0.85";
      shell = "zsh";
      update_check_interval = 0;

      clear_all_shortcuts = true;
    };
    keybindings =
      let
        leader = "ctrl+a>";
      in
      {
        "ctrl+equal" = "change_font_size all +2.0";
        "ctrl+minus" = "change_font_size all -2.0";
        "ctrl+0" = "change_font_size all 0";

        "${leader}t" = "new_tab";
        "${leader}n" = "next_tab";
        "${leader}p" = "previous_tab";

        "${leader}l" = "next_layout";
        "${leader}shift+t" = "new_window";
      };
  };
}
