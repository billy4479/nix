{
  lib,
  fetchFromGitHub,
  python3Packages,
  writeShellScript,
}:

python3Packages.buildPythonApplication {
  pname = "wa-crypt-tools";
  # The newest release tag is v0.1.0; master carries version 0.2.0 in
  # pyproject.toml, so the base version follows it and the date marks the
  # tracked commit.
  version = "0.2.0-unstable-2026-10-27";

  src = fetchFromGitHub {
    owner = "ElDavoo";
    repo = "wa-crypt-tools";
    rev = "b6f67453d19e443f53f57da0361f3ef5e8b6821d";
    hash = "sha256-beEHOrqx1MutS5fDuBqvlDwDzDc30Y+FDcAexRwM/f0=";
  };

  pyproject = true;

  build-system = with python3Packages; [
    setuptools
    setuptools-scm
  ];

  dependencies = with python3Packages; [
    javaobj-py3
    protobuf
    pycryptodomex
    # Split out of the interpreter in current nixpkgs; wagui needs it.
    tkinter
  ];

  doCheck = true;
  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
  ];

  # tests/tools-invocation runs the console scripts as subprocesses.
  preCheck = # sh
    ''
      export PATH="$out/bin:$PATH"
    '';

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-wa-crypt-tools";
  };

  meta = {
    description = "Manages WhatsApp .crypt12, .crypt14 and .crypt15 files, given the key";
    homepage = "https://github.com/ElDavoo/wa-crypt-tools";
    license = lib.licenses.gpl3Plus;
    mainProgram = "wadecrypt";
  };
}
