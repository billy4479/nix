{
  pkgs,
  extraConfig,
  ...
}: {
  services.dunst = {
    enable = true;
    iconTheme = import ../icons/papirus.nix {
      inherit pkgs;
      inherit (extraConfig) catppuccinColors;
    };

    settings = {
      # TODO: should try to upstream colors to ctp-nix
      global = {
        width = 300;
        height = 300;
        offset = "30x30";
        origin = "top-right";

        frame_color = "#8CAAEE";
        corner_radius = 10;
        font = "${(import ../fonts/names.nix).mono} 11";
      };
      urgency_low = {
        background = "#303446";
        foreground = "#C6D0F5";
        timeout = 5;
      };
      urgency_normal = {
        background = "#303446";
        foreground = "#C6D0F5";
        timeout = 5;
      };
      urgency_critical = {
        background = "#303446";
        foreground = "#C6D0F5";
        frame_color = "#EF9F76";
        timeout = 0;
      };
    };
  };
}
