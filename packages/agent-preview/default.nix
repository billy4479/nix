{ buildGoModule, lib }:

buildGoModule {
  pname = "agent-preview";
  version = "0.1.0";
  src = ./.;
  vendorHash = null;
  env.CGO_ENABLED = "0";

  meta = {
    description = "Lease-based preview relay for agent applications";
    mainProgram = "agent-preview";
    platforms = lib.platforms.linux;
  };
}
