{
  callPackage,
  pyproject-build-systems,
  pyproject-nix,
  uv2nix,
  ...
}:

let
  version = "3.0.4";
  source = callPackage ./source.nix { inherit version; };
  pythonEnv = callPackage ./python-env.nix {
    inherit
      pyproject-build-systems
      pyproject-nix
      source
      uv2nix
      version
      ;
  };
  stealthfox = callPackage ./stealthfox.nix {
    inherit pythonEnv;
  };
  geoip = callPackage ./geoip.nix { };
  byparr = callPackage ./package.nix {
    inherit
      geoip
      pythonEnv
      source
      stealthfox
      version
      ;
  };
in
{
  inherit
    byparr
    geoip
    pythonEnv
    source
    stealthfox
    ;
}
