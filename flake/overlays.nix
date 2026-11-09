{ inputs, system }:
[
  (
    final: prev:
    {
      inherit (inputs.ff.packages.${system}) ff;
      # The app flake exposes the binary as `default`; no mc-java
      # equivalent is needed: the image carries the java version
      # the world runs on (see the service file).
      game-server-runner = inputs.game-server-runner.packages.${system}.default;
      inherit (inputs.calendar-proxy.packages.${system}) calendar-proxy;
      inherit (inputs.giuoco-del-divertimento.packages.${system}) giuoco-del-divertimento;
      inherit (inputs.agent-up.packages.${system}) agent-up agent-up-server;
      quote-bot = inputs.quote-bot.packages.${system}.default;
      read-nix-docs = inputs.read-nix-docs.packages.${system}.default;
    }
    // (import ../packages {
      pkgs = prev;
      inherit inputs;
    })
  )
  inputs.nix-snapshotter.overlays.default
]
