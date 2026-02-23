{ ... }:
{
  imports = [
    # ./auto-cpufreq.nix # Apparently power-management-daemon is enabled by default now, we'll use that
    ./powertop.nix
  ];

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
