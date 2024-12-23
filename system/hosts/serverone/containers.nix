{ ... }:
{
  imports = [
    ../../../containers/syncthing.nix
  ];

  virtualisation = {
    podman = {
      enable = true;

      defaultNetwork.settings = {
        dns_enabled = true;
        subnets = [
          {
            gateway = "10.0.1.1";
            subnet = "10.0.1.0/24";
          }
        ];
      };
    };
    oci-containers.backend = "podman";
  };
}
