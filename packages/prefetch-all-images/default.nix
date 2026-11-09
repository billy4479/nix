{
  stdenvNoCC,
  makeWrapper,
  lib,
  coreutils,
  gawk,
  nix-prefetch-docker,
  nixfmt,
  ...
}:
stdenvNoCC.mkDerivation {
  name = "prefetch-all-images";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = # sh
    ''
      runHook preInstall

      install -Dv ${./prefetch-all-images} $out/bin/$name

      wrapProgram $out/bin/$name \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gawk
          nix-prefetch-docker
          nixfmt
        ]
      }

      runHook postInstall
    '';

  meta = {
    description = "Prefetch Docker images and generate their Nix expressions";
    mainProgram = "prefetch-all-images";
    platforms = lib.platforms.unix;
  };
}
