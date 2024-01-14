{
  pkgs,
  config,
  ...
}: {
  home.file."${config.xdg.userDirs.pictures}/wallpapers".source = pkgs.fetchFromGitHub {
    owner = "billy4479";
    repo = "wallpapers";
    rev = "c45b45d308eea9ceaa707f6524485ea538e2c67f";
    hash = "sha256-jm4dVQi24JevjnE5lBsQuOFURVwQku7cotyQeP3khjE=";
  };
}
