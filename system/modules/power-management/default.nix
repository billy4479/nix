{ ... }:
{
  imports = [
    # ./auto-cpufreq.nix # Apparently power-management-daemon is enabled by default now, we'll use that
    ./powertop.nix
  ];
}
