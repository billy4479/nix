{
  buildGoModule,
  fetchFromGitHub,
  go_1_27,

  lib,
  writeShellScript,
}:
(buildGoModule.override { go = go_1_27; }) (finalAttrs: {
  pname = "tsidp";
  version = "0.0.18";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tsidp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-oL+WH5iFVRd0erh3KfJrvUMIpZraomHoRzo5sh3duu0=";
  };

  patches = [
    ./headscale-proxy.patch
    ./public-clients.patch
    ./browser-rp-cors.patch
  ];

  vendorHash = "sha256-X3o71xgGBFJM3Sspb+223NYsDwJ3jf+9lCWQxS6JDA8=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/tailscale/tsidp/server.version=${finalAttrs.version}"
  ];

  doCheck = true;

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-tsidp";
  };

  meta = {
    description = "Tailscale OIDC Identity Provider";
    homepage = "https://github.com/tailscale/tsidp";
    license = lib.licenses.bsd3;
    mainProgram = "tsidp";
  };
})
