{
  pkgs,
  lib,
  extraConfig,
  ...
}:
if extraConfig.wayland
then {}
else {
  # Generated through nvidia-settings
  environment.etc."X11/xorg.conf.d/98-monitor.conf".text = ''
    Section "Monitor"
        # HorizSync source: edid, VertRefresh source: edid
        Identifier     "Monitor0"
        VendorName     "Unknown"
        ModelName      "GBT M27Q"
        HorizSync       243.0 - 243.0
        VertRefresh     48.0 - 165.0
        Option         "DPMS"
    EndSection

    Section "Device"
        Identifier     "Device0"
        Driver         "nvidia"
        VendorName     "NVIDIA Corporation"
        BoardName      "NVIDIA GeForce GTX 1060 6GB"
    EndSection

    Section "Screen"
        Identifier     "Screen0"
        Device         "Device0"
        Monitor        "Monitor0"
        DefaultDepth    24
        Option         "Stereo" "0"
        Option         "nvidiaXineramaInfoOrder" "DFP-1"
        Option         "metamodes" "DP-0: 2560x1440_170 +1920+0 {AllowGSYNCCompatible=On}, DP-2: 1920x1080_75 +0+0 {AllowGSYNCCompatible=On}"
        Option         "SLI" "Off"
        Option         "MultiGPU" "Off"
        Option         "BaseMosaic" "off"
        SubSection     "Display"
            Depth       24
        EndSubSection
    EndSection
  '';
}
