{
  callPackage,
  lib,
  nodejs-slim,
  pyproject-build-systems,
  pyproject-nix,
  python314,
  source,
  uv2nix,
  version,
  ...
}:

let
  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = source.sourcePath;
  };

  pythonSet =
    (callPackage pyproject-nix.build.packages {
      python = python314;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
          (final: prev: {
            playwright = prev.playwright.overrideAttrs (old: {
              # Reuse Nix's Node instead of retaining the bundled binary, which
              # is also incompatible with Nix's ELF post-processing.
              postInstall = (old.postInstall or "") + /* sh */ ''
                ln -sfn ${lib.getExe nodejs-slim} "$out/${python314.sitePackages}/playwright/driver/node"
              '';
            });

            byparr = prev.byparr.overrideAttrs (old: {
              # The application sources are shipped by package.nix; this venv
              # only needs Byparr's locked runtime dependencies.
              meta = (old.meta or { }) // {
                broken = true;
              };
            });

            "playwright-captcha" =
              (prev."playwright-captcha".override { sourcePreference = "sdist"; }).overrideAttrs
                (old: {
                  prePatch =
                    (old.prePatch or "")
                    # sh
                    + ''
                      sed -i 's/\r$//' playwright_captcha/utils/camoufox_add_init_script/add_init_script.py
                    '';
                  patches = (old.patches or [ ]) ++ [ ./patches/playwright-captcha-writable-addon.patch ];
                  postPatch =
                    (old.postPatch or "")
                    # sh
                    + ''
                      rm -f playwright_captcha/utils/camoufox_add_init_script/add_init_script.py.orig
                      rm -rf playwright_captcha/utils/camoufox_add_init_script/__pycache__
                    '';
                  nativeBuildInputs =
                    (old.nativeBuildInputs or [ ])
                    ++ final.resolveBuildSystem {
                      setuptools = [ ];
                    };
                });
          })
        ]
      );
in
pythonSet.mkVirtualEnv "byparr-python-env-${version}" {
  fastapi = [ "standard" ];
  invisible-playwright = [ ];
  playwright = [ ];
  "playwright-captcha" = [ ];
  pydantic = [ ];
  pydantic-settings = [ ];
  trafilatura = [ ];
}
