# Upload files from serverone to OpenCloud

The serverone Home Manager configuration installs `opencloud-upload`. It sends
files to a dedicated OpenCloud folder without using your account credentials or
changing the server's OIDC settings.

## Set up an inbox

1. In OpenCloud, create a folder such as `serverone inbox`.
2. In that folder's sharing settings, create a **File Drop** link, not an Edit
   link. File Drop lets the uploader add files without listing or reading the
   folder. Set a strong password, then copy the share URL.
3. On serverone, run `opencloud-upload setup` and paste the link when prompted.
   The link token is stored in `~/.config/opencloud-upload/token` (or under
   `$XDG_CONFIG_HOME`) with owner-only permissions. The password is not saved.

## Upload a file

```sh
opencloud-upload '/path/to/my report.pdf'
```

Enter the File Drop password when curl prompts for the password for `public`.
Check the inbox in OpenCloud to see the uploaded file. If the link is exposed,
revoke it in OpenCloud, create a new one, and run `opencloud-upload setup` again.
