{ pkgs
, extraConfig
, ...
}:
let
  srcs = pkgs.fetchFromGitHub {
    owner = "black7375";
    repo = "Firefox-UI-Fix";
    rev = "c79922aa45ff04a62e04ef0f8562dc53990b5208";
    hash = "sha256-Mtnoit1CAGJoc8eiJ+0vfGc9v+3tomm8V8/tWfeAj7o=";
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
