{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.lm_sensors ];

  boot.kernelModules = [
    "coretemp"
    "nct6775"
  ];
}
