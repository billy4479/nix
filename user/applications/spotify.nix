{ pkgs, extraPkgs, ... }:
let
  # Spotify urls - Thanks to https://community.spotify.com/t5/Desktop-Linux/Guide-Play-Spotify-links-in-running-client/td-p/4647308
  # Pair with https://greasyfork.org/en/scripts/38920-spotify-open-in-app
  spotify-open = pkgs.makeDesktopItem {
    name = "spotify-open";
    desktopName = "Open In Spotify";
    genericName = "Music Player";
    icon = "spotify-client";
    exec = "${pkgs.dbus}/bin/dbus-send --type=method_call --dest=org.mpris.MediaPlayer2.spotify /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.OpenUri string:%U";
    terminal = false;
    mimeTypes = [ "x-scheme-handler/spotify" ];
    categories = [ "Audio" "Music" "Player" "AudioVideo" ];
    startupWMClass = "spotify";
  };
in
{
  home.packages = [ spotify-open ];
  programs.spicetify = {
    enable = true;
    theme = extraPkgs.spicetifyPkgs.themes.catppuccin;
    colorScheme = "frappe";

    enabledExtensions = with extraPkgs.spicetifyPkgs.extensions; [
      fullAppDisplay
      shuffle
    ];
  };
}
