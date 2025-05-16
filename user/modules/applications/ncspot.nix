{ ... }:
{
  programs.ncspot = {
    enable = true;
    settings = {
      backend = "pulseaudio";
      shuffle = true;
      volnorm = true;
      notify = true;
      use_nerdfont = true;
    };
  };
}
