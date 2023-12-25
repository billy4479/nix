{ pkgs, user, ... }:

{
  programs.git = {
    enable = true;
    delta = {
      enable = true;
      options = {
        features = "side-by-side line-numbers decorations";
        whitespace-error-style = "22 reverse";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
        };
      };
    };

    extraConfig.color.ui = true;

    userEmail = if user.username == "billy" then "giachi.ellero@gmail.com" else throw "you should probably change this";
    userName = if user.username == "billy" then "billy4479" else throw "you should probably change this";
  };

  home.packages = with pkgs; [
    gh
  ];
}
