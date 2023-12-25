{ pkgs, config, ... }:

let
  aliases = {
    rebuild-nix = "sudo nixos-rebuild switch --flake $HOME/nix";
    rebuild-hm = "home-manager switch --flake $HOME/nix";

    cls = "clear";
    vim = "nvim";
    o = "xdg-open";

    ls = "eza -a --icons --color=auto --group-directories-first";
    ll = "ls -lh";

    mkcd = ''mkdir -p "$1" && cd "$1"'';
  };
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
    shellAliases = aliases;

    dirHashes = {
      c = "$HOME/code";
      s = "$HOME/src";
      dl = "$HOME/Downloads";
    };

    dotDir = ".config/zsh";
    history = {
      ignoreAllDups = true;
      path = "${config.xdg.dataHome}/zsh/zsh_history";
      save = 1000000;
      size = 1000000;
      share = true;
    };

    localVariables = {
      WORDCHARS = "";
    };

    initExtra = ''
      zstyle ':completion:*' menu select

      # Case insensitive
      zstyle ':completion:*' matcher-list "" 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

      # Include hidden files
      _comp_options+=(globdots)

      autoload bashcompinit
      bashcompinit

      # Key bindings
      bindkey "^[[H" beginning-of-line # HOME
      bindkey "^[[F" end-of-line # END
      bindkey "^[[3~" delete-char # DEL
      bindkey "^[[3;5~" delete-word # CTRL+DEL
      bindkey "^H" backward-delete-word # CTRL+BACKSPACE
      bindkey "^[[1;5C" forward-word # CTRL+ARROW_RIGHT
      bindkey "^[[1;5D" backward-word # CTRL+ARROW_LEFT
      bindkey "^Z" undo
      bindkey "^Y" redo

      # Arrow Up
      autoload -U up-line-or-beginning-search
      zle -N up-line-or-beginning-search
      bindkey "^[[A" up-line-or-beginning-search
      bindkey "^[OA" up-line-or-beginning-search
      
      # Arrow Down
      autoload -U down-line-or-beginning-search
      zle -N down-line-or-beginning-search
      bindkey "^[[B" down-line-or-beginning-search
      bindkey "^[OB" down-line-or-beginning-search

      setopt rmstarsilent
    '';
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    shellAliases = aliases;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = pkgs.lib.importTOML ./starship.toml;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.packages = with pkgs; [
    bat
    eza
  ];
}
