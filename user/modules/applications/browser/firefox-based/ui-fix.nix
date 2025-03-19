{
  extraConfig,
  flakeInputs,
  ...
}:
let
  srcs = flakeInputs.firefox-ui-fix;

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
