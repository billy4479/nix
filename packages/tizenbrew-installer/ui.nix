{
  buildNpmPackage,
  lib,
  nodejs,
  src,
  version,
}:

buildNpmPackage (finalAttrs: {
  pname = "tizenbrew-installer-ui";
  inherit version src;

  sourceRoot = "${finalAttrs.src.name}/client/ui";

  # The lockfile resolves react and react-dom to @preact/compat, which does
  # not satisfy the react peer range of @heroicons/react, react-i18next and
  # @noriginmedia/norigin-spatial-navigation; upstream installs with --force.
  # But --force makes npm re-resolve the conflicting peers from the registry,
  # which the fetched cache does not contain. Strip the react peers from the
  # lockfile instead: plain `npm ci` then installs the full lockfile tree
  # (including the peer-only @babel/core, terser and preact-render-to-string
  # the build needs) entirely from the cache.
  patches = [ ./relax-react-peers.patch ];

  npmDepsHash = "sha256-bA5fP3WPJFi/mjfqtjsBA26zifzlqQ2nALR6khL3/3s=";

  installPhase = # sh
    ''
      runHook preInstall
      # The output is the vite dist tree itself; the service installs it at
      # <root>/ui/dist and serves it statically.
      mkdir $out
      cp -R dist/. $out/
      runHook postInstall
    '';

  meta = {
    description = "Web UI for the TizenBrew Installer desktop service";
    homepage = "https://github.com/reisxd/TizenBrewInstaller";
    license = lib.licenses.gpl3Only;
    inherit (nodejs.meta) platforms;
  };
})
