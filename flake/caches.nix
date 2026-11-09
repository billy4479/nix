{
  cudaSupport ? false,
}:
let
  # Flake metadata requires literal settings, so keep the definitions in flake.nix.
  caches = (import ../flake.nix).nixConfig;
in
{
  substituters = builtins.filter (
    url: cudaSupport || url != "https://cache.nixos-cuda.org"
  ) caches.extra-substituters;
  trusted-public-keys = builtins.filter (
    key: cudaSupport || builtins.match "cache\\.nixos-cuda\\.org:.*" key == null
  ) caches.extra-trusted-public-keys;
}
