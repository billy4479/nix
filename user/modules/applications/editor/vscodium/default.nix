{
  pkgs,
  lib,
  extraPkgs,
  extraConfig,
  ...
}:
let
  font = (import ../../../fonts/names.nix).mono;
  fontStr = "'${font}', 'Ubuntu Mono', monospace";
in
{
  catppuccin.vscode.profiles.default = {
    enable = true;
    inherit (extraConfig.catppuccinColors) accent;
    settings = {
      boldKeywords = true;
      italicComments = true;
      italicKeywords = true;
      colorOverrides = { };
      customUIColors = { };
      workbenchMode = "default";
      bracketMode = "rainbow";
      extraBordersEnabled = false;
    };
  };

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    profiles.default = {
      extensions = (
        with extraPkgs.vscode-extensions.vscode-marketplace-release;
        [
          # Theme
          catppuccin.catppuccin-vsc-icons

          # Languages
          ms-python.python # Python
          mechatroner.rainbow-csv # CSV
          ms-toolsai.jupyter # Jupyter notebooks

          # Tools
          mkhl.direnv # Direnv
          streetsidesoftware.code-spell-checker # Spell checker
          charliermarsh.ruff # Ruff (python formatter)
          # github.copilot # Copilot
          # github.copilot-chat # Copilot Chat

          # IDE customization
          christian-kohler.path-intellisense # Path Intellisense
          gruntfuggly.todo-tree # Todo Tree
          wayou.vscode-todo-highlight # Todo Highlight
          vscodevim.vim # Vim motion
        ]
      );
      keybindings = [
        {
          key = "ctrl+[Semicolon]";
          command = "workbench.action.terminal.toggleTerminal";
        }
        {
          # Fix for italian keyboard
          key = "ctrl+shift+7";
          command = "editor.action.commentLine";
          when = "editorTextFocus && !editorReadonly";
        }
        {
          key = "ctrl+/";
          command = "-editor.action.commentLine";
          when = "editorTextFocus && !editorReadonly";
        }
        {
          key = "ctrl+enter";
          command = "-github.copilot.generate";
          when = "editorTextFocus && github.copilot.activated && !inInteractiveInput && !interactiveEditorFocused";
        }
      ];

      userSettings = lib.importJSON ./settings.json // {
        "editor.fontFamily" = fontStr;
        "terminal.integrated.fontFamily" = fontStr;
      };
    };
  };
}
