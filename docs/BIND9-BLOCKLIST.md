# Build a custom BIND9 blocklist

This repo's `bind9-hosts` Nix package runs the [StevenBlack hosts generator](https://github.com/StevenBlack/hosts)
against the feeds bundled in a pinned upstream release, then converts the output
into a BIND9 response policy zone (RPZ). No live feeds are fetched by the generator.

Edit [`blocklist.nix`](../services/services/bind9/blocklist.nix) to tune the list:

- `feeds`: `null` for all base feeds, `[]` for none, or a list of names from
  upstream's `data/` directory, such as `[ "adaway.org" "StevenBlack" ]`.
- `extensions`: any of `fakenews`, `gambling`, `porn`, and `social`.
- `allowlist`: domains to exclude from the blocklist, including their subdomains.
- `blocklist`: extra domains to block. Use bare domain names, not hosts-file lines.

Build and inspect the resulting zone:

```sh
nix build .#bind9-hosts --out-link result-blocklist
head result-blocklist
```

The BIND9 service uses the same settings. To build the standalone config and its
`blacklist.conf` without deploying anything, run `nix build .#bind9-config`.
To refresh the bundled feeds, update `version` and the source `hash` in
[`hosts.nix`](../services/services/bind9/hosts.nix).
