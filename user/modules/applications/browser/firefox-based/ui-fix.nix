{ pkgs, extraConfig, ... }:
let
  srcs = pkgs.fetchFromGitHub {
    owner = "black7375";
    repo = "Firefox-UI-Fix";
    rev = "530b283da01d898d75909385afffacef89ecaa19";
    hash = "sha256-iqBCjjjwx9uNr5E2eYz9gs9LRdPdTvKb46eZykYljPY=";
  };

  # TODO: support librewolf too
  profilePath = ".mozilla/firefox/${extraConfig.user.username}";
in
{
  home.file."${profilePath}/icons".source = "${srcs}/icons";

  programs.firefox.profiles.${extraConfig.user.username} = {
    extraConfig =
      "\n\n// --- Options from https://github.com/black7375/Firefox-UI-Fix ---\n\n "
      + (builtins.readFile "${srcs}/user.js");

    userChrome = builtins.readFile "${srcs}/css/leptonChrome.css";
    userContent = builtins.readFile "${srcs}/css/leptonContent.css";
  };
}
