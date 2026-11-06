{ pkgs, flakeInputs }:
let
  inherit (pkgs) lib;
  chromium =
    pkgs.writeShellScriptBin "chromium" # sh
      ''
        export FONTCONFIG_FILE=${
          pkgs.makeFontsConf {
            fontDirectories = [
              "${pkgs.dejavu_fonts}/share/fonts/truetype"
              "${pkgs.liberation_ttf}/share/fonts/truetype"
              "${pkgs.noto-fonts-color-emoji}/share/fonts/noto"
            ];
          }
        }
        exec ${lib.getExe pkgs.chromium} --no-sandbox --disable-dev-shm-usage "$@"
      '';
  agentBrowser =
    pkgs.writeShellScriptBin "agent-browser" # sh
      ''
        export AGENT_BROWSER_EXECUTABLE_PATH=${chromium}/bin/chromium
        exec ${lib.getExe pkgs.agent-browser} "$@"
      '';
  # Bundle the same headless formatter used on the desktops, but leave language
  # formatter executables to the project's devShell.
  hm = flakeInputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../../user/modules/applications/editor/nvim
      {
        home.username = "openchamber";
        home.homeDirectory = "/home/openchamber";
        home.stateVersion = "23.11";
      }
    ];
    extraSpecialArgs = {
      inherit flakeInputs;
      extraConfig.catppuccinColors = {
        flavor = "frappe";
        accent = "green";
        flavorWithAccent = "Frappé";
        upper = {
          flavor = "Frappe";
          accent = "Green";
          flavorWithAccent = "Frappé";
        };
      };
    };
  };
  nvimFmt = pkgs.symlinkJoin {
    name = "agent-nvim-fmt";
    paths = [
      (pkgs.callPackage ../../user/modules/applications/editor/nvim/fmt/package.nix {
        neovim = hm.config.programs.neovim.finalPackage;
      })
    ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = # sh
      ''
        mkdir -p "$out/config" "$out/data"
        ln -s ${hm.config.home-files}/.config/nvim "$out/config/nvim"
        ln -s ${hm.config.home-files}/.local/share/nvim "$out/data/nvim"
        wrapProgram "$out/bin/nvim-fmt" \
          --set XDG_CONFIG_HOME "$out/config" \
          --set XDG_DATA_HOME "$out/data"
      '';
  };
in
{
  inherit chromium agentBrowser nvimFmt;
  agentBrowserSkill = "${pkgs.agent-browser}/skills/agent-browser";
}
