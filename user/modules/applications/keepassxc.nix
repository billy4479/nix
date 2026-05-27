{
  ...
}:
{
  programs.keepassxc = {
    enable = true;
    autostart = true;
    settings = {
      General = {
        ConfigVersion = 2;
        MinimizeAfterUnlock = true;
      };
      Browser = {
        CustomProxyLocation = "";
        Enabled = true;
        UpdateBinaryPath = false;
      };
      FdoSecrets = {
        Enabled = true;
      };
      GUI = {
        ApplicationTheme = "classic";
        ColorPasswords = true;
        CompactMode = true;
        MinimizeOnClose = true;
        MinimizeOnStartup = true;
        MinimizeToTray = true;
        ShowTrayIcon = true;
        TrayIconAppearance = "monochrome-light";
      };
      PasswordGenerator = {
        AdditionalChars = "";
        AdvancedMode = true;
        ExcludeAlike = false;
        ExcludedChars = "";
        Length = 32;
        Logograms = true;
      };
      SSHAgent = {
        Enabled = true;
      };
      Security = {
        IconDownloadFallback = true;
      };
    };
  };

  # Disable `secrets` so that keepass is used instead
  services.gnome-keyring.components = [
    "pkcs11"
    "ssh"
  ];
}
