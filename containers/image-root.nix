{
  lib,
  dockerTools,
  coreutils,
  tini,
  buildEnv,
  symlinkJoin,
  writeTextDir,
  name,
  container,
}:
let
  user = container.userName;
  uid = toString container.uid;
  home = container.environment.HOME or "/var/empty";
  shell = container.environment.SHELL or "/bin/sh";
  identity = symlinkJoin {
    name = "${name}-container-identity";
    paths = [
      (writeTextDir "etc/passwd" ''
        root:x:0:0:root:/root:${shell}
        ${user}:x:${uid}:5000:User for container ${name}:${home}:${shell}
        nobody:x:65534:65534:nobody:/nonexistent:/bin/sh
      '')
      (writeTextDir "etc/group" ''
        root:x:0:
        containers:x:5000:${user}
        nogroup:x:65534:
      '')
      (writeTextDir "etc/nsswitch.conf" ''
        passwd: files
        group: files
        hosts: files dns
      '')
    ];
  };
in
buildEnv {
  name = "${name}-container-root";
  # A single merged tree avoids duplicate paths in snapshotter's root copier.
  # Explicit application packages take precedence over the shared defaults.
  paths =
    map lib.lowPrio [
      dockerTools.binSh
      dockerTools.caCertificates
      coreutils
      tini
      identity
    ]
    ++ container.copyToRoot;
  pathsToLink = [ "/" ];
  passthru = { inherit identity; };
}
