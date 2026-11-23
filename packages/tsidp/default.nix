{
  buildGoModule,
  fetchFromGitHub,
  go_1_27,

  lib,
  writeShellScript,
}:
(buildGoModule.override { go = go_1_27; }) (finalAttrs: {
  pname = "tsidp";
  version = "0.0.19";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tsidp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-tDQ8t4FRAMixY9JFWBMrejKlpv68YgagbpCfQS3rBl0=";
  };

  patches = [
    ./headscale-proxy.patch
    ./public-clients.patch
    ./browser-rp-cors.patch
  ];

  vendorHash = "sha256-bqdb0RkOxeifR/T+m93zpFcTDEEL7J+3YXuJo9sgKKE=";

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
