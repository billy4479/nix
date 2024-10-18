{ ... }:
{
  programs.direnv = {
    enable = true;
    enableZshIntegration = true; # I use zsh as my main shell, change this if you use bash
    nix-direnv.enable = true;
  };
}
