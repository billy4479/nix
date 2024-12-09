{ pkgs, extraConfig, ... }:
let
  srcs = pkgs.fetchFromGitHub {
    owner = "black7375";
    repo = "Firefox-UI-Fix";
    rev = "e5eff553fd4e33750157232a262d6430a7610e87";
    hash = "sha256-8sRUGrKcSBDzqIjACR7eRfn4VzFbL3zfRB8GDsNKO5A=";
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
