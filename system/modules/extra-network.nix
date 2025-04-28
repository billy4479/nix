{ ... }:
{
  # These are networking options which are only intended for the desktop systems
  networking.firewall = {
    # Various experiments are on 4479
    allowedTCPPorts = [ 4479 ];
    allowedUDPPorts = [ 4479 ];

    # KDE Connect ports
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };
}
