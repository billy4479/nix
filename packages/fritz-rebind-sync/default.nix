{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "fritz-rebind-sync";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  meta = {
    description = "Reconcile a FRITZ!Box DNS rebind exception list";
    mainProgram = "fritz-rebind-sync";
  };
}
