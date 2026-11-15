{ pkgs }:
pkgs.writeShellApplication {
  name = "display-mode";
  runtimeInputs = with pkgs; [
    niri
    rofi
    jq
    systemd
    wl-mirror
  ];
  text = builtins.readFile ./display-mode.sh;
}
