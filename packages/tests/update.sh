#!/usr/bin/env bash
# Exercise the update driver with local fixtures, without network or Nix builds.
set -euo pipefail

driver=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/update.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

git init -q "$tmp"
cd "$tmp"
git config user.name 'Update test'
git config user.email 'update@example.invalid'
mkdir -p packages/{changed,unchanged,failed,dirty}
cp "$driver" packages/update.sh
for pkg in changed unchanged failed dirty; do
  printf 'original\n' >"packages/$pkg/source"
done
printf '#!/usr/bin/env bash\nprintf "updated\\n" > changed/source\nprintf "new\\n" > changed/added\n' >packages/changed/update.sh
printf '#!/usr/bin/env bash\nexit 0\n' >packages/unchanged/update.sh
printf '#!/usr/bin/env bash\nprintf "partial\\n" > failed/source\nexit 1\n' >packages/failed/update.sh
printf '#!/usr/bin/env bash\ntouch dirty/ran\n' >packages/dirty/update.sh
chmod +x packages/*/update.sh
printf 'original\n' >unrelated
git add .
git commit -qm 'test: initial fixtures'
printf 'staged\n' >unrelated
git add unrelated
printf 'local\n' >packages/dirty/source

if bash packages/update.sh failed changed unchanged dirty; then
  echo 'expected failed and dirty packages to fail' >&2
  exit 1
fi
[[ $(git rev-list --count HEAD) == 2 ]]
[[ $(git log -1 --format=%s) == 'changed: update package' ]]
[[ $(git diff-tree --no-commit-id --name-only -r HEAD) == $'packages/changed/added\npackages/changed/source' ]]
[[ $(git diff --cached --name-only) == unrelated ]]
[[ $(git show HEAD:unrelated) == original ]]
[[ $(git show HEAD:packages/failed/source) == original ]]
[[ $(<packages/failed/source) == partial ]]
[[ ! -e packages/dirty/ran ]]

# A successful no-op must not create an empty commit.
bash packages/update.sh unchanged
[[ $(git rev-list --count HEAD) == 2 ]]
# Only direct package directory names are accepted.
if bash packages/update.sh ../packages/changed; then
  echo 'expected a path argument to be rejected' >&2
  exit 1
fi
printf 'Update driver tests passed\n'
