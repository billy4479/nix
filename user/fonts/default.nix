{
  pkgs,
  extraPkgs,
  ...
}: {
  home.packages = with pkgs; [
    extraPkgs.my-packages.apple-fonts
    (nerdfonts.override {
      fonts = ["FiraCode"];
    })
  ];
}
