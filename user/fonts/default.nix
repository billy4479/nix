{pkgs, ...}: {
  home.packages = with pkgs; [
    (callPackage ./apple-fonts.nix {})
    (nerdfonts.override {
      fonts = ["FiraCode"];
    })
  ];
}
