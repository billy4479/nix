{
  lib,
  python3,
  runCommand,
  stdenvNoCC,
  makeWrapper,
}:
let
  sources = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./agent_vm.py
      ./broker.py
      ./libvirt_vm.py
    ];
  };
in
stdenvNoCC.mkDerivation {
  pname = "agent-vm";
  version = "0.1.0";
  src = sources;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = # sh
    ''
      runHook preInstall
      mkdir -p "$out/lib/agent-vm"
      cp *.py "$out/lib/agent-vm/"
      makeWrapper ${lib.getExe python3} "$out/bin/agent-vm" \
        --add-flags "$out/lib/agent-vm/agent_vm.py"
      runHook postInstall
    '';

  passthru.tests.broker = runCommand "agent-vm-tests" { nativeBuildInputs = [ python3 ]; } ''
    cp ${sources}/*.py .
    cp ${./test_agent_vm.py} test_agent_vm.py
    python -m unittest -v
    touch "$out"
  '';

  meta = {
    description = "Lease and power control for a shared development VM";
    mainProgram = "agent-vm";
    platforms = lib.platforms.linux;
  };
}
