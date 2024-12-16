{ ... }:
{
  programs.btop = {
    enable = true;
    catppuccin.enable = true;

    settings = {
      "proc_per_core" = true;
      "proc_filter_kernel" = true;
    };
  };
}
