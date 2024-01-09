{...} @ args: let
  aboutConfig = {
    # Lets be honest, this is more annoying than useful
    "webgl.disabled" = false;
    "privacy.resistFingerprinting" = false;
    "extensions.pocket.enabled" = false;

    # Keep history
    "privacy.clearOnShutdown.history" = false;
    "privacy.clearOnShutdown.downloads" = false;
    "services.sync.prefs.sync-seen.privacy.clearOnShutdown.downloads" = false;
    "services.sync.prefs.sync-seen.privacy.clearOnShutdown.history" = false;
    "services.sync.prefs.sync-seen.privacy.clearOnShutdown.offlineApps" = false;

    # Disable password manager
    "services.sync.engine.passwords" = false;

    # Firefox Sync
    "identity.fxaccounts.enabled" = true;

    # Autoscroll
    "middlemouse.paste" = false;
    "general.autoScroll" = true;

    # Search engine
    "browser.search.separatePrivateDefault" = false;
    "browser.search.suggest.enabled" = true;
    "browser.urlbar.suggest.searches" = true;

    # Fonts
    "font.default.x-western" = "sans-serif";
    "font.name.monospace.x-western" = "FiraCode Nerd Font";
    "font.name.sans-serif.x-western" = "SF Pro Display";
    "font.name.serif.x-western" = "SF Pro Display"; # Basically disable serif fonts
    "browser.display.use_document_fonts" = 0; # No custom fonts

    "browser.aboutConfig.showWarning" = false;
    "browser.bookmarks.addedImportButton" = true;
    "browser.topsites.contile.cachedTiles" = "";
    "browser.uiCustomization.state" = builtins.readFile ./ui-state.json;
  };
in {
  imports = [
    (import ./firefox.nix (args // {inherit aboutConfig;}))
    # (import ./librewolf.nix (args // {inherit aboutConfig;}))
  ];
}
