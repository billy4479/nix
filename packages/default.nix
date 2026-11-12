{ pkgs, inputs }:
let
  inherit (pkgs) callPackage;
  byparrPackages = callPackage ./byparr {
    inherit (inputs) pyproject-build-systems pyproject-nix uv2nix;
  };
in
rec {
  google-sans = callPackage ./google-sans { };
  inherit (byparrPackages) byparr;
  byparr-source = byparrPackages.source;
  byparr-python-env = byparrPackages.pythonEnv;
  byparr-stealthfox = byparrPackages.stealthfox;
  byparr-geoip = byparrPackages.geoip;
  libvpl-tools = callPackage ./libvpl-tools { };
  derper = callPackage ./derper { };
  tsidp = callPackage ./tsidp { };
  lunamultiplayer-server = callPackage ./lunamultiplayer-server { };
  searxng-cli = callPackage ./searxng-cli { };
  openchamber-web = callPackage ./openchamber-web { inherit opencode; };
  opencode = callPackage ./opencode { };
  t3code = callPackage ./t3code { };
  wa-crypt-tools = callPackage ./wa-crypt-tools { };
  mircrewrr = callPackage ./mircrewrr { };
  tizenbrew-installer = callPackage ./tizenbrew-installer { };
}
