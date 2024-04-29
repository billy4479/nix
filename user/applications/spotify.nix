{ extraPkgs, ... }: {
  programs.spicetify = {
    enable = true;
    theme = extraPkgs.spicetifyPkgs.themes.catppuccin;
    colorScheme = "frappe";

    enabledExtensions = with extraPkgs.spicetifyPkgs.extensions; [
      fullAppDisplay
      shuffle
    ];
  };
}
