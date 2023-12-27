{ ... }@args:
let
  aboutConfig = {
    # Lets be honest, this is more annoying than useful
    "webgl.disabled" = false;
    "privacy.resistFingerprinting" = false;
    "extensions.pocket.enabled" = false;

    # Keep history
    "privacy.clearOnShutdown.history" = false;
    "privacy.clearOnShutdown.downloads" = false;

    # Firefox Sync
    "identity.fxaccounts.enabled" = true;

    # Autoscroll
    "middlemouse.paste" = false;
    "general.autoScroll" = true;

    # Search engine
    "browser.search.separatePrivateDefault" = false;
    "browser.search.suggest.enabled" = true;
    "browser.urlbar.suggest.searches" = true;

    "browser.aboutConfig.showWarning" = false;
    "browser.bookmarks.addedImportButton" = true;
    "browser.topsites.contile.cachedTiles" = "";
    "browser.uiCustomization.state" = builtins.readFile ./ui-state.json;
  };
in
{
  imports = [
    (import ./firefox.nix (args // { inherit aboutConfig; }))
    # (import ./librewolf.nix (args // {inherit aboutConfig;}))
  ];
}
