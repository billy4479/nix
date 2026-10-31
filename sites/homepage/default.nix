# Static content of polpetta.online (moved out of the billy4479.github.io
# repository). Served by serverone's nginx container, which mounts the
# result read-only at /srv/homepage.
{
  runCommand,
}:
runCommand "homepage" { } # sh
  ''
    mkdir -p $out
    install ${./index.html} $out/index.html
  ''
