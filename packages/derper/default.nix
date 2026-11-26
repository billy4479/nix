{
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
  go_1_27,

  lib,
  writeShellScript,
}:
let
  # Tailscale requires Go 1.27.4, newer than the current nixpkgs pin.
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
  pname = "derper";
  version = "1.104.7";

  src = fetchFromGitHub {
    owner = "tailscale";
    repo = "tailscale";
    rev = "v${finalAttrs.version}";
    hash = "sha256-6bCZpWZY4IYF5Vz/a65naqAa83IIPvmk2yuqet317n8=";
  };

  subPackages = [ "cmd/derper" ];

  vendorHash = "sha256-IJ0m56UP0RyMBE5eQeQ082EMJZfvrgE37lfPHE2ujCA=";

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
