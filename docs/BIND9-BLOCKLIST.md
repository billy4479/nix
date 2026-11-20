# Build a custom BIND9 blocklist

Use the [StevenBlack hosts generator](https://github.com/StevenBlack/hosts) to
choose what to block. Nix takes the resulting hosts file and converts its
`0.0.0.0` entries into BIND9 response policy (RPZ) records.

## Generate the hosts file

```sh
git clone https://github.com/StevenBlack/hosts.git stevenblack-hosts
cd stevenblack-hosts
git checkout f0c1e878685f647bac77f6ed81980379318ee7c3
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install -r requirements.txt
```

That commit is the one used by the current Nix configuration. Before building:

- **Base feeds:** keep the folders you want under `data/`. Remove unwanted feed
  folders from this checkout or move them outside it. To add a feed, use an
  existing `data/` folder as a template for `hosts` and `update.json`.
- **Categories:** use `--extensions` with any of `fakenews`, `gambling`, `porn`,
  and `social`. Omit the flag for base feeds only. Use `--nounifiedhosts` to
  omit base feeds and build from extensions instead.
- **Allow domains:** create `whitelist` with one domain per line. Allowing a
  domain also allows its subdomains.
- **Block extra domains:** create `blacklist` with lines like
  `0.0.0.0 ads.example.org`.

For example, build from your selected base feeds plus the gambling extension:

```sh
python3 updateHostsFile.py --auto --noupdate --nogendata --skipstatichosts \
  --extensions gambling --output generated
```

The result is `generated/hosts`. `--noupdate` uses the checked-out feed copies;
remove it to fetch fresh data. Leave out `--replace` so the generator does not
change your system hosts file. Leave out `--compress` so each entry stays on its
own line for BIND9 conversion.

## Use it in this Nix repo

Copy `generated/hosts` to `services/services/bind9/hosts.generated` in this
checkout. In [`hosts.nix`](../services/services/bind9/hosts.nix), replace the
whole `src = fetchurl { ... };` block with:

```nix
src = ./hosts.generated;
```

The converter still exempts `click.aliexpress.com` and its subdomains. If you
want the generator's whitelist to be the only source of exceptions, replace
`$0 !~ /(^|\.)click\.aliexpress\.com$/ { print $0 " CNAME ." }` in `hosts.nix`
with `{ print $0 " CNAME ." }`, and put any exceptions you want in `whitelist`.

Run `git add services/services/bind9/hosts.generated` so Nix can see the file
in the Git-backed flake. Then validate the configuration with:

```sh
nix build --no-link .#nixosConfigurations.serverone.config.system.build.toplevel
```

For later updates, rerun the generator and copy the new `generated/hosts` over
`hosts.generated` before rebuilding.
