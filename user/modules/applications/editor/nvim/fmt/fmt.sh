# Wrapper for the `fmt` CLI: expands directories to files (git-aware), then
# hands everything to the headless Neovim driver in ./fmt.lua. The @nvim@ and
# @lua@ placeholders are substituted by ./package.nix.
set -euo pipefail

# Avoid option-like filenames being parsed as flags by nvim.
normalize() {
	case "$1" in
	-*) "./$1" ;;
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
		echo "fmt: no such file or directory: $p" >&2
		exit 1
	fi
done

if [ "${#files[@]}" -eq 0 ]; then
	echo "fmt: nothing to format"
	exit 0
fi

exec @nvim@ --headless -l @lua@ "${files[@]}"
