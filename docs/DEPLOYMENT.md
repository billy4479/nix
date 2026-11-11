# Deployment controls: CI investigation

Before adding phone-friendly deployment controls, verify that GitHub-hosted
runners can build both server configurations. The current `build.yml` workflow
only builds: it does not deploy or provide rollback controls.

## Observed result

[Run 42636480416](https://github.com/billy4479/nix/actions/runs/42636480416),
commit `1e233ec227eb65128b3a380d324d1c8ae70d553b`:

- `vps-proxy` built successfully on `ubuntu-latest`.
- `serverone` failed fetching `calendar-proxy-v2` with `Repository not found`,
  on both attempts. It did not reach a full build, so this does not establish
  whether the runner has enough disk or memory for serverone.
- SSH agent setup reported that the deploy keys' comments did not match GitHub
  repository URLs. Without per-repository routing, GitHub can accept a key for
  a different repository and then deny access to the requested repository.

`scripts/ci-ssh.sh` now gives each private input an explicit SSH identity and
repository-specific Git URL rewrite. It does not depend on key comments. The
existing five Actions secrets remain required, with read access to their
respective repositories. No secret values need changing if the keys already
have the correct access.

Offline regression tests:

```sh
python3 tests/ci-ssh.py
```

## Next verification

After the fix reaches GitHub, manually run **Build NixOS configurations** from
the Actions tab. Inspect `serverone` for build errors, `No space left on device`,
OOM termination, or runner timeout. An authentication failure still needs fixing
before assessing capacity. The agent's current GitHub credentials cannot
trigger this workflow (HTTP 403), inspect Actions secrets, or inspect the private
calendar repository's deploy keys.

If the hosted runner cannot accommodate serverone, use a private, authenticated
mobile dashboard with builds on serverone for both hosts. The VPS should only
receive and activate prebuilt closures. Rollback should select a retained system
generation without rebuilding, and direct SSH recovery must remain available
if the dashboard or network fails. System rollback does not restore application
data or undo database migrations.

No deployment or dashboard has been activated as part of this investigation.
