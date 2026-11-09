{
  lib,
  buildDotnetModule,
  fetchFromGitHub,

  dotnet-sdk_10,
  dotnet-runtime_10,
  writeShellScript,
}:
let
  version = "0.29.2";

  src = fetchFromGitHub {
    repo = "LunaMultiplayer";
    owner = "LunaMultiplayer";
    rev = version;
    hash = "sha256-50x2d1xZRJFHA02D2U121IhRm5RH2cVZManRYAFHeTY=";
  };
in
buildDotnetModule {
  pname = "lunamultiplayer-server";
  inherit version src;

  projectFile = [
    "Server/Server.csproj"
  ];
  executables = [ "Server" ];

  dotnet-sdk = dotnet-sdk_10;
  dotnet-runtime = dotnet-runtime_10;

  patches = [ ./change-working-dir.diff ];

  postPatch = # sh
    ''
      substituteInPlace global.json \
        --replace-fail '"version": "6.0.403"' '"version": "${dotnet-sdk_10.version}"'
      substituteInPlace \
        Lidgren.Core/Lidgren.Core.csproj \
        LmpMasterServer/LmpMasterServer.csproj \
        LmpMasterServerTest/LmpMasterServerTest.csproj \
        MasterServer/MasterServer.csproj \
        Server/Server.csproj \
        ServerTest/ServerTest.csproj \
        --replace-fail "<TargetFramework>net6.0</TargetFramework>" "<TargetFramework>net10.0</TargetFramework>"
      substituteInPlace Server/Utilities/DotNetRuntimeChecker.cs \
        --replace-fail "private const int RequiredMajorVersion = 6;" "private const int RequiredMajorVersion = 10;" \
        --replace-fail 'private const string RequiredRuntimeName = ".NET 6.0 Runtime";' 'private const string RequiredRuntimeName = ".NET 10.0 Runtime";' \
        --replace-fail 'private const string RuntimeDownloadUrl = "https://dotnet.microsoft.com/en-us/download/dotnet/6.0";' 'private const string RuntimeDownloadUrl = "https://dotnet.microsoft.com/en-us/download/dotnet/10.0";'
    '';

  nugetDeps = ./deps.json;

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-lunamultiplayer-server";
  };

  meta = {
    description = "Luna Multiplayer server for Kerbal Space Program";
    homepage = "https://github.com/LunaMultiplayer/LunaMultiplayer";
    license = lib.licenses.mit;
    mainProgram = "Server";
    inherit (dotnet-runtime_10.meta) platforms;
  };
}
