---
name: agent-vm
description: Use agent-vm to lease, reset, or release a disposable NixOS VM or the headless Android emulator. Use for guest sudo, isolated builds, APK testing, ADB, Gradle connected tests, or Appium.
---

Choose a unique, non-secret profile name per agent session and reuse it across shell calls and session restarts. A fork needs a different profile. Use `--profile NAME` or set `AGENT_VM_PROFILE` on every command. Do not copy profiles or put their files in the workspace.

```sh
export AGENT_VM_PROFILE=my-unique-task-id
agent-vm request shared
agent-vm queue
agent-vm wait --timeout 120
```

Use `request exclusive` instead if you need sole access, guest-wide changes, or power/reset control. Do not hold a shared lease while waiting for exclusive access on another profile. Once an exclusive request is queued, later shared requests wait behind it. `wait` does not cancel requests on timeout; use `cancel` if abandoning a request, or `release` if it has already been granted. `status` shows the remaining time. Leases last 30 minutes and can be renewed with `renew`, even while others wait. Renew deliberately for long jobs, not indefinitely.

Once active, use standard OpenSSH and SCP:

```sh
vm_ssh=$(agent-vm ssh-config)
scp -F "$vm_ssh" ./input.txt agent-vm:~/input.txt
ssh -F "$vm_ssh" agent-vm 'uname -a; sudo -n true'
scp -F "$vm_ssh" agent-vm:~/result.txt ./result.txt
agent-vm release
```

## Android app testing

Use the same CLI with `--android` before the subcommand. Android is always exclusive and shares the NixOS queue; do not hold either guest while waiting for the other. Use a different profile for each independent request.

```sh
export AGENT_VM_PROFILE=my-unique-android-task
agent-vm --android request
agent-vm --android wait --timeout 180
adb_env=$(agent-vm --android adb-env) && eval "$adb_env"
adb devices
adb install ./app.apk
adb exec-out screencap -p >screenshot.png
# Or run ./gradlew connectedDebugAndroidTest in the configured shell.
agent-vm --android release
unset ADB_SERVER_SOCKET ANDROID_ADB_SERVER_PORT ANDROID_SERIAL
```

Only use ADB after `wait` and `adb-env` succeed. `adb-env` starts a local server for the lease; run it once and share its exports with any test subprocesses. For Appium, run the server in the same T3 container and shell environment, and configure `appium:udid` as `$ANDROID_SERIAL` and `appium:adbPort` as the numeric `$ANDROID_ADB_SERVER_PORT`. Set up `adb-env` again after `agent-vm --android reset`. Reset, release, and expiry erase Android data and disconnect the old ADB session; pull artifacts first. No SSH, manual power control, GUI, Google Play, or host ADB listener is provided.

## NixOS guest details

Shared holders have sudo and can see or modify each other's guest state. Use separate working directories and do not copy secrets, host keys, or fleet credentials into the VM. There are no host workspace mounts. Copy out changes and artifacts before release. The final release or expiry closes connections, stops the VM, and wipes the guest disk. Expiry of one shared holder closes their connection without wiping the remaining holders' work.

With an exclusive lease, use `off` and `on` to power-cycle while preserving disk state. `reset` starts over from a clean image without releasing the lease. After a reset, run `ssh-config` again. If the broker reports a fault, report it to the user; do not try to manage the host hypervisor directly.
