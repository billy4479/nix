{
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
  go_1_27,

  lib,
  writeShellScript,
}:
let
  # tsidp needs Go 1.27.4, newer than the current nixpkgs pin.
  go =
    if lib.versionAtLeast go_1_27.version "1.27.4" then
      go_1_27
    else
      go_1_27.overrideAttrs {
        version = "1.27.4";
        src = fetchurl {
          url = "https://go.dev/dl/go1.27.4.src.tar.gz";
          hash = "sha256-c8+4VxrsDAEXdofbhxY9Rqog6XeWcncokaoXZU2aYJk=";
        };
      };
in
(buildGoModule.override { inherit go; }) (finalAttrs: {
  pname = "tsidp";
  version = "0.0.21";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tsidp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-1tWxqV+V4jbdhVVMQ+oxmIArs6puEK9UNAdLlT38pE0=";
  };

  patches = [
    ./headscale-proxy.patch
    ./public-clients.patch
    ./browser-rp-cors.patch
  ];

  vendorHash = "sha256-jbAFoiM/bhVkuxzCeUzgVCPt1Z3vNVEqtpW02Z5TaSo=";

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
