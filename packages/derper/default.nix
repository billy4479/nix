{
  buildGoModule,
  fetchFromGitHub,
  go_1_27,

  lib,
  writeShellScript,
}:
(buildGoModule.override { go = go_1_27; }) (finalAttrs: {
  pname = "derper";
  version = "1.104.4";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tailscale";
    rev = "v${finalAttrs.version}";
    hash = "sha256-sJh3oXFarS1s+flMfm4ZAE+0ZSwp8F3Rib76+qBFVIw=";
  };

  subPackages = [ "cmd/derper" ];

  vendorHash = "sha256-RvaouD88naVNOPJBVcqMaAn+ovjXI4g83ShCdRiR5/Q=";

  ldflags = [
    "-s"
    "-w"
    "-X tailscale.com/version.longStamp=${finalAttrs.version}"
    "-X tailscale.com/version.shortStamp=${finalAttrs.version}"
  ];

  passthru.updateScript = import ../lib/make-update-script.nix {
    inherit writeShellScript;
    pkgPath = ./.;
    name = "update-derper";
  };

  meta = {
    description = "Standalone Tailscale DERP relay and STUN server";
    homepage = "https://github.com/tailscale/tailscale";
    license = lib.licenses.bsd3;
    mainProgram = "derper";
  };
})
