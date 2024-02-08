{
  pkgs,
  lib,
  extraConfig,
  ...
}: {
  programs.autorandr = {
    enable = true;
    profiles = {
      "computerone" = {
        fingerprint = {
          DP-0 = "00ffffffffffff001c540d2701010101261e0104b5462778fbcb85a75335b6250d50542fcf00d1c001010101010181809500b3000101ee6000a0a0a052503020680c544f2100001e000000fd0030a5f3f33c010a202020202020000000fc004d3237510a2020202020202020000000ff003230333830423030393338360a02cf02033f714902031112042f903f05230917078301000067030c001000383c67d85dc4017880036d1a0000020130aa000000000000e305e301e606050164641e94fb0050a0a028500820a804544f2100001e3ec200a0a0a055503020f80c544f2100001ed58980c870384d404420f80c544f2100001e000000000000000000007a70122e00000301140e0b0100ff099f002f801f009f052700190007000301145fe80000ff0977001b001f009f056600000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000090";
          DP-2 = "00ffffffffffff0005e36a24b1f00100171c0104a5351e783bf6e5a7534d9924145054bfef00d1c0b30095008180814081c001010101023a801871382d40582c4500132b2100001e6842806a7038274008209804132b2100001e000000fd00234c535311010a202020202020000000fc003234363047350a20202020202001d502031ef14b901f051404130312021101230907078301000065030c0010008c0ad08a20e02d10103e9600132b21000018011d007251d01e206e285500132b2100001e8c0ad08a20e02d10103e9600132b210000188c0ad090204031200c405500132b210000180000000000000000000000000000000000000000000000000031";
        };
        config = {
          DP-2 = {
            enable = true;
            crtc = 1;
            mode = "1920x1080";
            position = "0x0";
            rate = "74.99";
            gamma = "1.19:1.0:0.833";
          };
          DP-0 = {
            mode = "2560x1440";
            position = "1920x0";
            rate = "169.83";
            crtc = 0;
            gamma = "1.19:1.0:0.833";
            primary = true;
          };
        };
      };
    };
  };

  systemd.user.services.autorandr = {
    Unit = {
      Description = "autorandr";
    };

    Install = {WantedBy = ["autostart.target"];};

    Service = {
      ExecStart = "${lib.getExe pkgs.autorandr} --load ${extraConfig.hostname}";
      Type = "oneshot";
    };
  };
}