{ extraConfig, ... }:
{
  programs.kitty = {
    enable = true;
    font = {
      name = (import ../../fonts/names.nix).mono;
      size = 16;
    };
    shellIntegration.enableZshIntegration = true;
    catppuccin.enable = true;
    settings = {
      copy_on_select = false;
      enable_audio_bell = false;
      window_padding_width = 0;
      confirm_os_window_close = 0;
      background_opacity = if extraConfig.desktop == "kde" then "1" else "0.7";
      shell = "zsh";
      update_check_interval = 0;
    };
    keybindings = {
      "ctrl+plus" = "change_font_size all +2.0";
      "ctrl+minus" = "change_font_size all -2.0";
      "ctrl+0" = "change_font_size all 0";
    };
  };
}
