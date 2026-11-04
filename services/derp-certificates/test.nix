{
  runCommand,
  python3,
  openssl,
}:
runCommand "derp-certificate-transfer-test"
  {
    nativeBuildInputs = [
      python3
      openssl
    ];
  }
  # sh
  ''
    cp ${./certificates.py} certificates.py
    cp ${./test.py} test.py
    python3 test.py -v
    touch "$out"
  ''
