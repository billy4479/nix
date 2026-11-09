{
  lib,
  stdenv,
  fetchFromGitHub,

  cmake,
  pkg-config,
  ninja,

  libvpl,
  libva,
  libdrm,
  libX11,
  libxcb,
  wayland,
  wayland-scanner,
  wayland-protocols,
  gtkmm4,
  libepoxy,
  libpciaccess,
  writeShellScript,
}:

stdenv.mkDerivation {
  pname = "libvpl-tools";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "intel";
    repo = "libvpl-tools";
    rev = "3de25bf3358de6d68633aeb915a2564808197315";
    hash = "sha256-0nE3cAUzdArf1QOsbFhBowaTqTVkNk4ZhJKJz311H6s=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wayland-scanner
  ];

  cmakeFlags = [
    "-DENABLE_WAYLAND=ON"
    "-DENABLE_GTK4=ON"
  ];

  buildInputs = [
    libvpl
    libva
    libdrm
    libX11
    libxcb
    wayland
    wayland-protocols
    gtkmm4
    libepoxy
    libpciaccess
  ];

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-libvpl-tools";
  };

  meta = {
    description = "Intel® Video Processing Library (Intel® VPL) Tools";
    homepage = "https://github.com/intel/libvpl-tools";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
