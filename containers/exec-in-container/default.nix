{
  lib,
  nerdctl,
  rustPlatform,

  allowedContainers,
}:
rustPlatform.buildRustPackage {
  pname = "exec-in-container";
  version = "0.1.0";

  src = lib.cleanSource ./.;

  cargoLock.lockFile = ./Cargo.lock;

  env = {
    NERDCTL_PATH = lib.getExe nerdctl;
    CONTAINERD_ADDRESS = "/run/containerd/containerd.sock";
    CONTAINERD_NAMESPACE = "default";
    ALLOWED_CONTAINERS = lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: uid: "${name}\t${toString uid}:5000") allowedContainers
    );
  };

  meta = {
    description = "Run commands as fixed users in configured nerdctl containers";
    license = lib.licenses.mit;
    mainProgram = "exec-in-container";
    platforms = lib.platforms.linux;
  };
}
