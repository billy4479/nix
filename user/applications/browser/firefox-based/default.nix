{ ... }@args:
let
  fonts = import ../../../fonts/names.nix;
  aboutConfig = {
    # Lets be honest, this is more annoying than useful
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
    "signon.rememberSignons" = false;
    "signon.generation.enabled" = false;
    "signon.firefoxRelay.feature" = "disabled";
    "signon.autofillForms" = false;

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
    "font.name.monospace.x-western" = fonts.mono;
    "font.name.sans-serif.x-western" = fonts.sans;
    "font.name.serif.x-western" = fonts.serif;
    "browser.display.use_document_fonts" = 0; # No custom fonts

    "browser.aboutConfig.showWarning" = false;
    "browser.bookmarks.addedImportButton" = true;
    "browser.topsites.contile.cachedTiles" = "";
    "browser.uiCustomization.state" = builtins.readFile ./ui-state.json;
    "browser.toolbars.bookmarks.visibility" = "always"; # Always show bookmarks

    # Find bar prefereces
    "findbar.highlightAll" = true;
    "accessibility.typeaheadfind.enablesound" = false;

    # Hardware acceleration - https://github.com/elFarto/nvidia-vaapi-driver?tab=readme-ov-file#firefox
    "media.ffmpeg.vaapi.enabled" = true;
    "media.rdd-ffmpeg.enabled" = true;
    "gfx.x11-egl.force-enabled" = true;
    "widget.dmabuf.force-enabled" = true;
    "webgl.disabled" = false;
    "gfx.webrender.all" = true;
  };
in
{
  imports = [
    (import ./firefox.nix (args // { inherit aboutConfig; }))
    # (import ./librewolf.nix (args // {inherit aboutConfig;}))

    # Add {userchrome,usercontent}.css, disable if you don't like it
    ./ui-fix.nix
  ];
}
