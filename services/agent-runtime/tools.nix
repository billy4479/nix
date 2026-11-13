{ pkgs }:
with pkgs;
[
  searxng-cli
  read-nix-docs
  agent-up
  curl
  diffutils
  fd
  file
  findutils
  gawk
  gh
  git
  gnugrep
  gnumake
  gnused
  gnutar
  gzip
  jq
  p7zip
  poppler-utils
  patch
  procps
  ripgrep
  util-linux
  which
  xz
  zstd
  (python3.withPackages (
    p: with p; [
      numpy
      scipy
      sympy
      pandas
      matplotlib
      pillow
      pypdf
      pyyaml
      requests
      beautifulsoup4
    ]
  ))
]
