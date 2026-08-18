{ lib, ... }:
{
  catppuccin.tmux.enable = true;
  programs.tmux = {
    enable = true;
    historyLimit = 10000;
    keyMode = "vi";
    mouse = true;
    shortcut = "b";
  };

  programs.zsh.initContent =
    lib.mkAfter # sh
      ''
        if [[ -n "$SSH_CONNECTION" && -z "$TMUX" && -t 0 ]]; then
          exec tmux new-session -A -s ssh
        fi
      '';

  programs.bash.initExtra = # sh
    ''
      if [[ -n "$SSH_CONNECTION" && -z "$TMUX" && -t 0 ]]; then
        exec tmux new-session -A -s ssh
      fi
    '';
}
