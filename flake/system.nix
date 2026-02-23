{
  system,
  inputs,
}@args:
let
  defaultOptions = {
    desktop = "kde";
    wayland = true;
    bluetooth = true;
    games = false;
    isServer = false;
    standaloneHomeManager = true;
    rotateMonitor = false; # only for computerone
    hasCuda = false;

    catppuccin = {
      flavor = "frappe";
      accent = "green";
    };

    user = {
      username = "billy";
      fullName = "Billy Panciotto";
    };
  };

  createAndMergeHosts = import ./createAndMergeHosts.nix args;
in
createAndMergeHosts defaultOptions [
  {
    hostname = "nixbox";
    args = {
      bluetooth = false;
    };
    extraSystemModules = [
      ../system/hosts/vm
    ];
  }
  {
    hostname = "portatilo";
    args = {
      desktop = "niri";
    };
    extraSystemModules = [
      ../system/hosts/portatilo
    ];
  }
  {
    hostname = "computerone";
    args = {
      desktop = "niri";
      # wayland = false;
      games = true;
      rotateMonitor = true;
      hasCuda = true;
    };
    extraSystemModules = [
      ../system/hosts/computerone
    ];
  }
  {
    hostname = "serverone";
    args = {
      isServer = true;
      standaloneHomeManager = false;
      bluetooth = false;
    };
    extraSystemModules = [
      ../system/hosts/serverone
    ];
  }
  {
    hostname = "vps-proxy";
    args = {
      isServer = true;
      standaloneHomeManager = false;
      bluetooth = false;
    };
    extraSystemModules = [
      ../system/hosts/vps-proxy
    ];
  }
]
