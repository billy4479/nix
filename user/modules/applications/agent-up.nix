# Human-accessible agent-up CLI, so files can be uploaded from a shell and
# shared with agents as a URL. Agents get their own copy through the opencode
# wrapper (see editor/opencode/artifacts.nix); keep AGENTUP_URL in sync there.
{ pkgs, ... }:
{
  home.packages = [
    (pkgs.symlinkJoin {
      name = "agent-up";
      paths = [ pkgs.agent-up ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = # sh
        ''
          wrapProgram "$out/bin/agent-up" \
            --set AGENTUP_URL "https://agent-up.internal.polpetta.online"
        '';
    })
  ];
}
