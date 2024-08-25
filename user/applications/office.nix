{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.programs.office;
in
{
  options.programs.office = {
    enableLibreOffice = lib.mkEnableOption "Enable LibreOffice";
    enableOnlyOffice = lib.mkEnableOption "Enable OnlyOffice";
  };

  config = {
    home.packages =
      [ ]
      ++ (
        if cfg.enableLibreOffice then
          with pkgs;
          [
            libreoffice-qt
            hunspell
            hunspellDicts.en_US
            hunspellDicts.it_IT
          ]
        else
          [ ]
      )
      ++ (if cfg.enableOnlyOffice then with pkgs; [ onlyoffice-bin ] else [ ]);
  };
}
