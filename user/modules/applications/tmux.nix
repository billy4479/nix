{ ... }:
{
  catppuccin.tmux.enable = true;
  programs.tmux = {
    enable = true;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    shortcut = "b";
  };
}
