{ extraConfig, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        email =
          if extraConfig.user.username == "billy" then
            "giachi.ellero@gmail.com"
          else
            throw "you should probably change this";
        name =
          if extraConfig.user.username == "billy" then
            "billy4479"
          else
            throw "you should probably change this";
      };

      color.ui = true;
      init.defaultBranch = "master";
    };

  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
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

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };
}
