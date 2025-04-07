{ aboutConfig, extraConfig, ... }:
{
  programs.firefox = {
    enable = true;
    profiles.${extraConfig.user.username} = {
      id = 0;
      search = {
        default = "Brave Search";
        engines = {
          "Brave Search" = {
            urls = [ { template = "https://search.brave.com/search?q={searchTerms}"; } ];
            icon = "https://brave.com/static-assets/images/brave-logo-sans-text.svg";
            updateInterval = 24 * 60 * 60 * 1000; # every day
          };
        };
        force = true;
      };
      settings = aboutConfig;
    };
  };
}
