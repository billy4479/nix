{
  pkgs,
  system,
  my-packages,
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
    args = { };
    extraSystemModules = [
      ../system/hosts/portatilo
    ];
  }
  {
    hostname = "computerone";
    args = {
      desktop = "qtile";
      wayland = false;
      games = true;
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
]
