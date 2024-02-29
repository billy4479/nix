{config, ...}: {
  home.file."${config.xdg.dataHome}/scripts" = {
    source = ./files;
  };
}
