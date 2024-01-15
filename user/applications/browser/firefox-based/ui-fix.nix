{
  pkgs,
  config,
  extraConfig,
  ...
}: let
  srcs = pkgs.fetchFromGitHub {
    owner = "black7375";
    repo = "Firefox-UI-Fix";
    rev = "f19eb3000da841b8e4f0686eebd450e5bab75d78";
    hash = "sha256-nSjUXj3TJOG4oY8YZaz/g96EypvcpVRPM7pCdBkXmMA=";
  };

  # TODO: support librewolf too
  profilePath = ".mozilla/firefox/${extraConfig.user.username}";
in {
  programs.firefox.profiles.${extraConfig.user.username} = {
    extraConfig =
      "\n\n// --- Options from https://github.com/black7375/Firefox-UI-Fix ---\n\n "
      + (builtins.readFile "${srcs}/user.js");

    userChrome = builtins.readFile "${srcs}/css/leptonChrome.css";
    userContent = builtins.readFile "${srcs}/css/leptonContent.css";
  };
}
