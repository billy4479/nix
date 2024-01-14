{...}: {
  services.gammastep = {
    enable = true;
    temperature = {
      day = 4900;
      night = 4900;
    };
    tray = true;

    # These are arbitrary, since I keep the same temperature all the time
    dawnTime = "6:00-8:00";
    duskTime = "17:00-19:00";
  };
}
