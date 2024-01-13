{spicetifyPkgs, ...}: {
  programs.spicetify = {
    enable = true;
    theme = spicetifyPkgs.themes.catppuccin;
    colorScheme = "frappe";

    enabledExtensions = with spicetifyPkgs.extensions; [
      fullAppDisplay
      shuffle
    ];
  };
}
