{
  runCommand,
  python3,
  nodejs_26,
  stdenv,
  t3code,
}:

runCommand "t3code-web-test"
  {
    nativeBuildInputs = [
      python3
      nodejs_26
    ];
  }
  # sh
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    python ${./test.py} ${t3code} ${t3code.version} ${stdenv.shell}
    touch "$out"
  ''
