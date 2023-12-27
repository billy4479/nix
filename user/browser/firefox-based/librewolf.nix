{ aboutConfig, ... }:

{
  programs.librewolf = {
    enable = true;

    # https://librewolf.net/docs/settings
    settings = aboutConfig;
  };
}
