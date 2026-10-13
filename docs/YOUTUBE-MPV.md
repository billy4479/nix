# YouTube to mpv

A userscript that adds a button and a `Ctrl+M` shortcut on YouTube watch/shorts
pages which hands the current video to the local mpv player.

## How it works

```
YouTube page --(userscript)--> mpv://open/<url-encoded-url>
             --(xdg mimeApps)--> mpv-open.desktop
             --(exec)--> mpv-open <uri> --> mpv <url>
```

- The userscript navigates to `mpv://open/<percent-encoded url>` on trigger.
  Firefox shows its external-protocol dialog; tick *Always allow* to skip it in
  the future.
- The `mpv://` scheme is handled by `mpv-open.desktop`, registered as the
  default application for `x-scheme-handler/mpv` in `user/modules/xdg-open.nix`.
- `mpv-open` (in `user/modules/scripts/packages.nix`) percent-decodes the url,
  refuses anything that isn't `http(s)://`, and spawns mpv detached from the
  browser process.

mpv resolves the stream itself via its built-in ytdl hook.

## Troubleshooting

If Firefox logs *“Prevented navigation to … due to an unknown protocol”* when
triggering the script, the running Firefox instance was started before
`mpv-open.desktop` was registered: it only discovers OS protocol handlers at
startup. Restart Firefox and try again. The handler is registered correctly
once `xdg-mime query default x-scheme-handler/mpv` prints `mpv-open.desktop`.
As a last resort, set `network.protocol-handler.external.mpv` to `true` in
`about:config` to skip the OS lookup entirely.

## Install the userscript

The script lives at
`user/modules/applications/browser/userscripts/youtube-mpv.user.js` (not
installed by nix — userscript managers manage their own storage).

With Tampermonkey/Violentmonkey:

1. Open the userscript manager dashboard
2. Create a new script / utility tab
3. Paste the contents of the file and save

## Components

| Piece                | Where                                                                |
| -------------------- | -------------------------------------------------------------------- |
| Userscript           | `user/modules/applications/browser/userscripts/youtube-mpv.user.js`  |
| `mpv-open` script    | `user/modules/scripts/packages.nix`                                  |
| Desktop registration | `user/modules/xdg-open.nix` (`x-scheme-handler/mpv`)                 |

Deployed on non-server machines only (`user/modules/scripts/default.nix`).

## Trigger

- `Ctrl+M` on any YouTube watch/shorts page
- The `mpv` button injected in the video action bar (falls back to a floating
  button if YouTube's DOM changes)

The tab's player is paused before handing off so audio doesn't keep playing in
the background.
