{ ... }:
{
  catppuccin.btop.enable = true;
  programs.btop = {
    enable = true;

    settings = {
      "proc_per_core" = true;
      "proc_filter_kernel" = true;
    };
  };
}
