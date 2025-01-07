{ lib, extraConfig, ... }:
let
  rotationStr = if extraConfig.rotateMonitor then " {rotation=left}" else "";
  bigMonitorPosition = if extraConfig.rotateMonitor then "+1080+0" else "+1920+0";
  metamodes = lib.strings.concatStringsSep ", " [
    "DP-0: 2560x1440_170 ${bigMonitorPosition}"
    "DP-2: 1920x1080_75 +0+0${rotationStr}"
  ];
in
{
  services.xserver = {
    # To get this I used nvidia-settings and copied the screen section
    # from the generated X.org config
    screenSection = ''
      Option         "nvidiaXineramaInfoOrder" "DP-0"
      Option         "metamodes" "${metamodes}"
      Option         "SLI" "Off"
      Option         "MultiGPU" "Off"
      Option         "BaseMosaic" "off"
      SubSection     "Display"
          Depth       24
      EndSubSection
    '';

    # This doensn't seam to do anything...
    xrandrHeads = [
      {
        output = "DP-0";
        primary = true;
        monitorConfig = ''
          Option "PreferredMode" "2560x1440_169.83"
          Option "Position" "1920 0"
          Option "DPMS"
        '';
      }
      {
        output = "DP-2";
        monitorConfig = ''
          Option "PreferredMode" "1920x1080_74.99"
          Option "Position" "0 0"
          Option "DPMS"
        '';
      }
    ];
  };

  # This is surely not working
  # https://discourse.nixos.org/t/proper-way-to-configure-monitors/12341/12
  # services.xserver.displayManager.setupCommands = ''
  #   LEFT='DP-2'
  #   RIGHT='DP-0'
  #   xrandr \
  #     --output $RIGHT --mode 2560x1440 --rate 169.83 --primary \
  #     --output $LEFT  --mode 1920x1080 --rate 74.99  --left-of $RIGHT
  # '';
}
