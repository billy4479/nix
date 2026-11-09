# T3 Code web

This package builds the web client and Node.js server from source, without the
desktop app, Electron, or mobile workspaces. The executable is `t3`:

```sh
nix run .#t3code -- --no-browser --host 127.0.0.1 --port 3773
```

Node.js, Git and GitHub CLI are provided by the package. Provider executables
and other external tools come from the caller's `PATH`, so you can supply them
in your own wrapper. No coding agent or browser is installed automatically.

Update with `./t3code/update.sh`. Run the web-server and native-terminal check
with `nix build .#t3code.tests.web`.
