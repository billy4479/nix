{
  extraConfig,
  flakeInputs,
  config,
  ...
}:
let
  srcs = flakeInputs.firefox-ui-fix;
in
{
  home.file."${config.programs.firefox.configPath}/${extraConfig.user.username}/icons".source =
    "${srcs}/icons";

  programs.firefox.profiles.${extraConfig.user.username} = {
    extraConfig =
      "\n\n// --- Options from https://github.com/black7375/Firefox-UI-Fix ---\n\n "
      + (builtins.readFile "${srcs}/user.js");

    userChrome = builtins.readFile "${srcs}/css/leptonChrome.css";
    userContent = builtins.readFile "${srcs}/css/leptonContent.css";
  };
}
