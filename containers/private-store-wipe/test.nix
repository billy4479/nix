{
  runCommand,
  callPackage,
  sqlite,
}:
let
  wipe = callPackage ./. { };
in
runCommand "private-store-threshold-test"
  {
    nativeBuildInputs = [
      wipe
      sqlite
    ];
  }
  # sh
  ''
    root="$TMPDIR/private-root"
    mkdir -p "$root/nix/var/nix/db"
    db="$root/nix/var/nix/db/db.sqlite"
    sqlite3 "$db" 'create table ValidPaths (narSize integer); insert into ValidPaths values (1073741823);'
    private-store-wipe "$root" 1
    test -f "$db"
    sqlite3 "$db" 'update ValidPaths set narSize = 1073741824;'
    private-store-wipe "$root" 1
    test -f "$db"
    sqlite3 "$db" 'update ValidPaths set narSize = 1073741825;'
    private-store-wipe "$root" 1
    test ! -e "$root/nix"
    private-store-wipe "$root" 1
    mkdir -p "$root/nix/var/nix/db"
    echo invalid >"$db"
    if private-store-wipe "$root" 1; then exit 1; fi
    test -f "$db"
    if private-store-wipe / 1; then exit 1; fi
    if private-store-wipe "$root" nonsense; then exit 1; fi
    if private-store-wipe "$root" 0; then exit 1; fi
    test -f "$db"
    touch "$out"
  ''
