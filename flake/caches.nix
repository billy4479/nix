{
  cudaSupport ? false,
}:
{
  substituters = [
    "https://nix-community.cachix.org"
    "https://catppuccin.cachix.org"
    "https://install.determinate.systems"
    "https://cache.nixos.org/"
    "https://noctalia.cachix.org"
  ]
  ++ (if cudaSupport then [ "https://cache.nixos-cuda.org" ] else [ ]);
  trusted-public-keys = [
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "computerone-1:FwphMHwxn0KLInwuouQcqsNn4J5fkzJNAd4QlJa4Lk8="
    "portatilo-1:KM4PhszcXObDUqfnN0BZNwnya6B+2br39PURy8hy6nA="
  ]
  ++ (
    if cudaSupport then [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ] else [ ]
  );
}
