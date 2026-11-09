#!/usr/bin/env bash
# Update packages: everything with an update.sh by default, or the ones named
# as arguments. Continues past failures and reports them at the end.
#
#   ./packages/update.sh                 # all packages
#   ./packages/update.sh derper tsidp    # a subset
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$here"

if (($#)); then
  packages=("$@")
else
  packages=()
  for dir in */; do
    dir=${dir%/}
    if [[ -x $dir/update.sh ]]; then
      packages+=("$dir")
    fi
  done
fi

if ((${#packages[@]} == 0)); then
  echo "nothing to update" >&2
  exit 0
fi

failed=()
for pkg in "${packages[@]}"; do
  if [[ ! -x $pkg/update.sh ]]; then
    echo "==> $pkg: no update.sh, skipping" >&2
    continue
  fi
  echo "==> updating $pkg"
  if "./$pkg/update.sh"; then
    echo "==> $pkg ok"
  else
    echo "==> $pkg FAILED" >&2
    failed+=("$pkg")
  fi
done

if ((${#failed[@]} > 0)); then
  echo "failed packages: ${failed[*]}" >&2
  exit 1
fi
