{ ... }:
{
  programs.zellij = {
    enable = true;
    # enableZshIntegration = true;
    catppuccin.enable = true;

    # https://www.reddit.com/r/NixOS/comments/1ealycu/comment/lemhigr/
    settings = {
      default_layout = "compact";
      pane_frames = false;
      keybinds = {
        "unbind \"Ctrl h\"" = { }; # This conflicts with Ctrl Backspace

        move = {
          "unbind \"Ctrl h\"" = { }; # This conflicts with Ctrl Backspace
          "bind \"Ctrl m\"".SwitchToMode = {
            _args = [ "Normal" ];
          };
        };

        normal = {
          "bind \"Alt H\" \"Alt K\"".GoToPreviousTab = { };
          "bind \"Alt L\" \"Alt J\"".GoToNextTab = { };
        };
      };
    };
  };
}
