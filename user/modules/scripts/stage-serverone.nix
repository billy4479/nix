{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "stage-serverone";
      runtimeInputs = with pkgs; [
        coreutils
        git
        gnutar
      ];
      text = builtins.readFile ./stage-serverone.sh;
    })
  ];
}
