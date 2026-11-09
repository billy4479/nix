{
  inputs,
  system,
  overlays,
  cudaSupport ? false,
}:
import inputs.nixpkgs {
  inherit system overlays;
  config = {
    allowUnfree = true;
    inherit cudaSupport;
  };
}
