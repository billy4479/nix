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
  freeProvider = pkgs.fetchFromGitHub {
    owner = "kslamph";
    repo = "pi-free-provider";
    rev = "763c9f953eab98ec5ae696cfb1b2e13f2dc07ff7"; # v0.2.5
    hash = "sha256-xvTlq2Ka5T7oB1wD7ZCe7AL/Y8zzN9YwNHR3MvdeyYQ=";
  };
in
pkgs.runCommand "pi-container-extensions" { } # sh
  ''
    mkdir -p "$out/rpiv-ask-user-question/node_modules/@juicesharp" "$out/t3code-reload" "$out/workspace"
    cp -r ${rpiv}/packages/rpiv-ask-user-question/. "$out/rpiv-ask-user-question/"
    cp -r ${rpiv}/packages/rpiv-config "$out/rpiv-ask-user-question/node_modules/@juicesharp/rpiv-config"
    cp ${reload}/{index.ts,package.json,LICENSE,README.md} "$out/t3code-reload/"
    mkdir -p "$out/free-provider"
    cp ${freeProvider}/{index,github,contract,feeds,network,capabilities,mapping,registry,auth,state,stream,tui,sidecar,zen-sidecar}.ts \
      ${freeProvider}/{package.json,LICENSE,README.md,INSTALL.md} "$out/free-provider/"
    mkdir -p "$out/free-provider/sources"
    cp ${freeProvider}/sources/{cline,opencode,opencode-config,opencode-contract,opencode-identity,opencode-system-prompt,types}.ts \
      "$out/free-provider/sources/"
    cp ${./workspace.ts} "$out/workspace/index.ts"
    cp ${./operations.ts} "$out/workspace/operations.ts"
  ''
