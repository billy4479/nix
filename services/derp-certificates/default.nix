{
  writeShellApplication,
  python3,
  openssl,
  systemd,
}:
writeShellApplication {
  name = "derp-certificates";
  runtimeInputs = [
    python3
    openssl
    systemd
  ];
  text = # sh
    ''
      exec python3 ${./certificates.py} "$@"
    '';
}
