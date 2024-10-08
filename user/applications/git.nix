{ extraConfig, ... }:
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

    extraConfig = {
      color.ui = true;
      init.defaultBranch = "master";
    };

    userEmail =
      if extraConfig.user.username == "billy" then
        "giachi.ellero@gmail.com"
      else
        throw "you should probably change this";
    userName =
      if extraConfig.user.username == "billy" then
        "billy4479"
      else
        throw "you should probably change this";
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}
