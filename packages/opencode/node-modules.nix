{
  lib,
  stdenvNoCC,
  bun,
  fetchFromGitHub,
  hash ?
    (lib.pipe ./hashes.json [
      builtins.readFile
      builtins.fromJSON
    ]).nodeModules.${stdenvNoCC.hostPlatform.system},
}:
let
  version = "2.2.5";

  src' = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = "sha256-/a1czcXi12KWPXcESqplNdOZcjEs8gWCMO7w4nQYLkw=";
  };

  # Filtered to what the node_modules install and the CLI build need.
  # packages/script reads .github/TEAM_MEMBERS, and the CLI build imports
  # script/native-arch.ts from the repo root.
  src = lib.sourceByRegex src' [
    "^packages(/.*)?$"
    "^services(/.*)?$"
    "^script(/.*)?$"
    "^bun\\.lock$"
    "^package\\.json$"
    "^patches(/.*)?$"
    "^\\.github(/TEAM_MEMBERS)?$"
  ];

  packageJson = lib.pipe (src + /package.json) [
    builtins.readFile
    builtins.fromJSON
  ];

  platform = stdenvNoCC.hostPlatform;
  bunCpu = if platform.isAarch64 then "arm64" else "x64";
  bunOs = if platform.isLinux then "linux" else "darwin";
in
assert packageJson.version == version;

stdenvNoCC.mkDerivation {
  pname = "opencode-node_modules";
  inherit version src;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
    "GIT_PROXY_COMMAND"
    "SOCKS_SERVER"
  ];

  nativeBuildInputs = [ bun ];

  dontConfigure = true;

  buildPhase = # sh
    ''
      runHook preBuild
      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --cpu="${bunCpu}" \
        --os="${bunOs}" \
        --filter '!./' \
        --filter './packages/cli' \
        --filter './packages/desktop' \
        --filter './packages/app' \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress
      bun --bun ${./scripts/canonicalize-node-modules.ts}
      bun --bun ${./scripts/normalize-bun-binaries.ts}
      runHook postBuild
    '';

  installPhase = # sh
    ''
      runHook preInstall
      mkdir -p $out
      find . -type d -name node_modules -exec cp -R --parents {} $out \;
      runHook postInstall
    '';

  dontFixup = true;

  outputHashMode = "recursive";
  outputHash = hash;

  meta.platforms = [
    "aarch64-linux"
    "x86_64-linux"
    "aarch64-darwin"
  ];
}
