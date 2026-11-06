{ pkgs }:
let
  rpiv = pkgs.fetchFromGitHub {
    owner = "juicesharp";
    repo = "rpiv-mono";
    rev = "46dbdfd78ab631bbf3ce41c2618bb173a5ec2725";
    hash = "sha256-YcW9if11TjR47wMnDv15UZBmg9NihqWbQ5HVhywgLzI=";
  };
  reload = pkgs.fetchFromGitHub {
    owner = "rldzkl";
    repo = "pi-t3code-reload";
    rev = "bbd8f95a4b239d247f61e6572db9b197c942c40e";
    hash = "sha256-9o/Xpw/lPsm4Gv+wLM/FCuENvX7o2aRBGXgwKlnXp7M=";
  };
in
pkgs.runCommand "pi-container-extensions" { } # sh
  ''
    mkdir -p "$out/rpiv-ask-user-question/node_modules/@juicesharp" "$out/t3code-reload" "$out/workspace"
    cp -r ${rpiv}/packages/rpiv-ask-user-question/. "$out/rpiv-ask-user-question/"
    cp -r ${rpiv}/packages/rpiv-config "$out/rpiv-ask-user-question/node_modules/@juicesharp/rpiv-config"
    cp ${reload}/{index.ts,package.json,LICENSE,README.md} "$out/t3code-reload/"
    cp ${./workspace.ts} "$out/workspace/index.ts"
    cp ${./operations.ts} "$out/workspace/operations.ts"
  ''
