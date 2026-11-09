{
  lib,
  openssl,
  pkg-config,
  rustPlatform,
  fetchFromGitea,
}:

rustPlatform.buildRustPackage {
  pname = "searxng-cli";
  version = "0.1.0";

  src = fetchFromGitea {
    domain = "codeberg.org";
    owner = "slundi";
    repo = "searxng";
    rev = "5fbf5ccd9a9386bc5d016bfa80a7d68e71e3ce89";
    hash = "sha256-L41yUfOvkRTLlfLYZvKV8xvc3ANUSNl6UpYBiBKn3rI=";
  };

  cargoLock.lockFile = ./Cargo.lock;

  patches = [
    ./fix-response-deserialization.patch
    ./compact-output.patch
    ./default-compact.patch
    ./english-output.patch
    ./limit-option.patch
    ./env-config.patch
    ./search-only-cli.patch
  ];

  postPatch = # sh
    ''
      cp ${./Cargo.lock} Cargo.lock
    '';

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = {
    description = "Asynchronous CLI and client library for SearXNG";
    homepage = "https://codeberg.org/slundi/searxng";
    license = lib.licenses.asl20;
    mainProgram = "searxng";
  };
}
