# Wrapper for the `nvim-fmt` CLI: expands directories to files (git-aware), then
# hands everything to the headless Neovim driver in ./fmt.lua. The nvim and
# driver paths are substituted by ./package.nix.
set -euo pipefail

usage() {
  cat <<'EOF'
nvim-fmt [path...]

Format files with the same conform.nvim setup the interactive Neovim
config uses, including treesitter-injected code blocks.

Paths can be files or directories: directories are expanded
recursively to tracked and untracked (not git-ignored) files, ignored
files are only formatted when passed explicitly. With no arguments
the current directory is formatted.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac

# Avoid option-like filenames being parsed as flags by nvim.
normalize() {
  case "$1" in
  -*) printf './%s' "$1" ;;
  *) printf '%s' "$1" ;;
  esac
}

if [ "$#" -eq 0 ]; then
  set -- "."
fi

files=()
for p in "$@"; do
  p=$(normalize "$p")
  if [ -d "$p" ]; then
    # tracked + untracked (not ignored) files; ignored files are skipped on
    # purpose, pass them explicitly to format them anyway. Falls back to
    # find outside of git repositories.
    while IFS= read -r -d '' f; do
      f="$p/$f"
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        files+=("$f")
      fi
    done < <(cd "$p" && {
      git ls-files -z --cached --others --exclude-standard 2>/dev/null ||
        find . -name .git -prune -o -type f -print0
    })
  elif [ -e "$p" ]; then
    files+=("$p")
  else
    echo "nvim-fmt: no such file or directory: $p" >&2
    exit 1
  fi
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "nvim-fmt: nothing to format"
  exit 0
fi

exec @nvim@ --headless -l @lua@ "${files[@]}"
