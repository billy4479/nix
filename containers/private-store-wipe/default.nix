{
  writeShellApplication,
  sqlite,
  coreutils,
}:
writeShellApplication {
  name = "private-store-wipe";
  runtimeInputs = [
    sqlite
    coreutils
  ];
  text = builtins.readFile ./wipe.sh;
}
