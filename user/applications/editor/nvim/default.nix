{ pkgs, config, ... }:
{
  # We don't use programs.neovim on purpose,
  # for now we just need to get a working AstroVim setup.
  # When I'll finally decide myself to learn vim properly I'll update this.

  home.packages = [ pkgs.neovim ];
  home.file = {
    "${config.xdg.configHome}/nvim" = {
      source = pkgs.fetchFromGitHub {
        owner = "AstroNvim";
        repo = "AstroNvim";
        rev = "271c9c3f71c2e315cb16c31276dec81ddca6a5a6";
        hash = "sha256-h019vKDgaOk0VL+bnAPOUoAL8VAkhY6MGDbqEy+uAKg=";
      };
      recursive = true;
    };
    "${config.xdg.configHome}/nvim/lua/user".source = ./user;
  };
}
