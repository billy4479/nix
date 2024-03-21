{
  pkgs,
  extraPkgs,
  ...
}: {
  home.packages = with pkgs; [
    prismlauncher
    # extraPkgs.my-packages.packwiz-installer # TODO: uncomment this once i figure out the grale build
    packwiz
  ];

  # Yeah, yeah, this is not plasma, but same config file format
  programs.plasma = {
    enable = true;
    dataFile."PrismLauncher/prismlauncher.cfg"."General" = {
      # These are the options we need in order to skip the first run wizard
      "ApplicationTheme" = "system";
      "BackgroundCat" = "kitteh";
      "ConfigVersion" = "1.2";
      "IconTheme" = "pe_colored";
      "JavaPath" = "${pkgs.jdk17}/bin/java";
      "Language" = "en_US";
      "LastHostname" = "computerone";
      "MaxMemAlloc" = "8192";
      "MinMemAlloc" = "512";
      "ToolbarsLocked" = "false";
      "UseSystemLocale" = "true";

      # This is extra stuff I also like
      "ConsoleFont" = (import ../../fonts/names.nix).mono;
    };
  };
}
