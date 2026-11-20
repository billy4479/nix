{
  lib,
  curl,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "fritz-rebind-sync";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  env.CURL_PATH = lib.getExe curl;
  meta = {
    description = "Reconcile a FRITZ!Box DNS rebind exception list";
    mainProgram = "fritz-rebind-sync";
  };
}
