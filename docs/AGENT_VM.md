# Shared agent development VM

`agent-vm` is a standalone CLI and broker, not a Pi extension. The T3 Code container gets the CLI, the [agent-vm skill](../.agents/skills/agent-vm/SKILL.md), and a restricted Unix socket. It does not get the libvirt socket or host sudo. Host-side administrators can also use the CLI as root. No TCP control listener is exposed.

`serverone` hosts one transient libvirt domain. Its minimal NixOS image has 2 vCPUs, 3 GiB RAM, and a 32 GiB virtual disk. The storage service provisions `ssd_pool/agent-vm` with a 36 GiB quota on first use. Every new group of holders starts with a fresh copy of the image and new guest SSH keys. The broker requires the dedicated dataset to be mounted before touching the disk. The guest has public IPv4 egress only through the LAN uplink; it has no inbound LAN route, private network access, IPv6 egress, host mounts, or fleet credentials. Services already exposed to the public internet remain reachable as public services. This does not change the agents' separate, existing host SSH permissions.

## Validation and rollout

Build the image and system on `serverone` or with a KVM-capable Nix builder. The T3 Code container does not have `/dev/kvm`.

```sh
nix build --no-link .#agent-vm .#agent-vm.tests.broker
nix build --no-link .#nixosConfigurations.serverone.config.system.build.agentVMImage
nix build --no-link .#nixosConfigurations.serverone.config.system.build.toplevel
```

Before making the socket available to agents, confirm spare memory under normal load and perform a live acceptance test after activating the configuration: boot the VM, SSH in with `agent-vm ssh-config`, verify guest sudo and SCP both ways, and verify public package access but no host, LAN, or tailnet access. Create a marker file, power-cycle it with an exclusive lease and verify the marker remains, then reset and verify it is gone. With distinct profiles, check that an exclusive waiter blocks new shared grants, the first shared release does not interrupt a second holder, and the final release disconnects SSH and resets the disk.

Leases and queue positions survive a **client** restart if it selects the same profile. Profiles are private files, not security isolation between agents running under the same Unix account; shared guest sudo is not isolation either. A **broker** restart invalidates all requests and leases and discards the disk before accepting new ones. Queued requests expire after two hours. Renewals can keep other requests waiting; an exclusive holder can stop the VM without releasing its lease. Power-off attempts a graceful ACPI shutdown, then forces it off after 20 seconds if necessary.

For a latched fault, inspect `journalctl -u agent-vm -u agent-vm-storage -u libvirtd`. After fixing the underlying problem, restart `agent-vm.service`; the broker verifies that the previous VM is stopped before serving. For maintenance, stop both `agent-vm.socket` and `agent-vm.service` so clients cannot reactivate it. To re-enable access, start `agent-vm.socket`.
