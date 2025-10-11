{ config, extraPkgs, ... }:
let
  containerName = "calendar-proxy";
in
{
  sops.secrets.calendar-proxy-env = { };

  virtualisation.oci-containers.containers."${containerName}" = {
    image = "localhost/calendar-proxy:latest";
    imageFile = extraPkgs.my-packages.containers.calendar-proxy;
    user = "5000:5000";

    environment = {
      PORT = "4479";
      ENV = "prod";
    };

    environmentFiles = [ config.sops.secrets.calendar-proxy-env.path ];

    extraOptions = [
      "--ip=10.0.1.4"
      "--tmpfs"
      "/tmp"
    ];
  };
}
