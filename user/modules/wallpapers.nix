{ pkgs, config, ... }:
{
  home.file."${config.xdg.userDirs.pictures}/wallpapers".source = pkgs.fetchFromGitHub {
    owner = "billy4479";
    repo = "wallpapers";
    rev = "2c362bb492d9ebbfffa06c1ddcc1ebea0a8d279a";
    hash = "sha256-jA13+mwv0hyodDQhwckT8F2DFsdMViuR8NCoG9k+T+s=";
  };
}
