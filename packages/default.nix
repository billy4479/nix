{pkgs}: let
  inherit (pkgs) callPackage;
in {
  apple-fonts = callPackage ./apple-fonts {};
  packwiz-installer = callPackage ./packwiz-installer {};
}
