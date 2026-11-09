# Turns a package's update.sh into a passthru.updateScript executable. The
# script is inlined and UPDATE_COMMON points at the bundled copy of the shared
# helpers, so it also works when invoked from a store path.
{
  writeShellScript,
  pkgPath, # the package directory containing update.sh
  name ? "update-script",
}:
writeShellScript name # sh
  ''
    export UPDATE_COMMON=${./update-common.sh}
    ${builtins.readFile (pkgPath + "/update.sh")}
  ''
