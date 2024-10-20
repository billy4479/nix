{ ... }:
{
  imports = [
    ../../../containers/syncthing.nix
  ];

  virtualisation = {
    podman = {
      enable = true;

      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
  };
}
