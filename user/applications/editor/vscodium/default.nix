{
  pkgs,
  lib,
  extraPkgs,
  ...
}: {
  nixpkgs.overlays = [extraPkgs.catppuccin-vsc.overlays.default];

  home.packages = with pkgs; [
    clang-tools
    nixd
    alejandra
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    # TODO: should we install them just in certain dev environments?
    extensions = with extraPkgs.vscode-extensions.vscode-marketplace;
      [
        # Theme
        catppuccin.catppuccin-vsc-icons

        # Languages
        jnoortheen.nix-ide # Nix
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
        github.copilot # Copilot
        mkhl.direnv # Direnv

        # IDE customization
        christian-kohler.path-intellisense # Path Intellisense
        zignd.html-css-class-completion # CSS Classes Intellisense
        gruntfuggly.todo-tree # Todo Tree
        wayou.vscode-todo-highlight # Todo Highlight
      ]
      ++ [
        # Less then ideal because of https://github.com/catppuccin/vscode/issues/218 but this is still the best option we have
        (pkgs.catppuccin-vsc.override {
          accent = "green";
          boldKeywords = true;
          italicComments = true;
          italicKeywords = true;
          extraBordersEnabled = false;
          workbenchMode = "default";
          bracketMode = "rainbow";
          colorOverrides = {};
          customUIColors = {};
        })
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
      {
        key = "ctrl+enter";
        command = "-github.copilot.generate";
        when = "editorTextFocus && github.copilot.activated && !inInteractiveInput && !interactiveEditorFocused";
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
    userSettings =
      lib.importJSON ./settings.json
      // {
        "editor.fontFamily" = (import ../../../fonts/names.nix).mono;
        "clangd.path" = "${pkgs.clang-tools}/bin/clangd"; # TODO: should this be in a devEnvironment?
      };
  };
}
