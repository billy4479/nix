{ extraConfig, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/autologin.nix
    ../../modules/bluetooth.nix
    ../../modules/containers.nix
    ../../modules/iphone.nix
    ../../modules/graphics/intel.nix
    ../../modules/power-management
    ../../modules/desktops

    ../../modules/cifs-client.nix
    ../../modules/smartd.nix
    ../../modules/tailscale.nix
    ../../modules/extra-network.nix
  ];

  networking.hostName = "portatilo";

  # Stay-awake mode runs systemd-inhibit from a user unit, which has no logind
  # session attached. Allow this user to hold the lid-switch inhibitor without
  # an interactive polkit prompt.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.login1.inhibit-handle-lid-switch" &&
          subject.user == "${extraConfig.user.username}") {
        return polkit.Result.YES;
      }
    });
  '';

  swapDevices = [
    {
      device = "/swapfile";
      options = [
        "defaults"
        "nofail"
      ];
      size = 32 * 1024;
    }
  ];
}
