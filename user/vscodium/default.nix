{ pkgs, lib, vscode-extensions, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    extensions = with vscode-extensions.vscode-marketplace; [
      # Theme
      # catppuccin.catppuccin-vsc # Disabled due to https://github.com/nix-community/nix-vscode-extensions/issues/46
      catppuccin.catppuccin-vsc-icons

      # Languages
      bbenoist.nix # Nix
      rust-lang.rust-analyzer # Rust
      golang.go # Go
      twxs.cmake # CMake
      ms-python.python # Python
      james-yu.latex-workshop # Latex
      llvm-vs-code-extensions.vscode-clangd # C/C++ (clangd)

      # Tools
      esbenp.prettier-vscode # Prettier
      dbaeumer.vscode-eslint # Eslint
      bradlc.vscode-tailwindcss # Tailwind
      vadimcn.vscode-lldb # LLDB
      xaver.clang-format # Clang Format

      # IDE customization
      christian-kohler.path-intellisense # Path Intellisense
      zignd.html-css-class-completion # CSS Classes Intellisense
      gruntfuggly.todo-tree # Todo Tree
      wayou.vscode-todo-highlight # Todo Highlight
    ];
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
    ];
    languageSnippets.go = {
      "Error handling" = {
        prefix = "errh";
        body = [
          "if \${1:err} != nil {"
          "\\tlog.Fatal(\${1:err})"
          "}"
          ""
        ];
      };
    };
    userSettings = lib.importJSON ./settings.json;
  };
}
