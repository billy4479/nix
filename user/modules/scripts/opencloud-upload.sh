usage() {
  printf 'Usage: opencloud-upload setup | opencloud-upload [--] FILE\n'
}

die() {
  printf 'opencloud-upload: %s\n' "$*" >&2
  exit 1
}

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/opencloud-upload"
token_file="$config_dir/token"

case ${1:-} in
  -h|--help) usage; exit 0 ;;
  setup)
    [[ $# == 1 ]] || die 'setup takes no arguments'
    read -r -s -p 'Paste the OpenCloud File Drop link: ' link </dev/tty || die 'could not read the link'
    printf '\n' >&2
    prefix="$origin/s/"
    token=${link#"$prefix"}
    token=${token%/}
    [[ $link == "$prefix"* && $token =~ ^[A-Za-z0-9]+$ ]] || die "expected a link like $prefix<TOKEN>"

    umask 077
    mkdir -p -- "$config_dir"
    temp=$(mktemp -- "$config_dir/token.XXXXXX")
    trap 'rm -f -- "$temp"' EXIT
    printf '%s\n' "$token" >"$temp"
    mv -fT -- "$temp" "$token_file"
    printf 'Inbox saved. To upload, run: opencloud-upload FILE\n'
    exit 0
    ;;
  --) shift ;;
esac

[[ $# == 1 ]] || { usage >&2; exit 2; }
[[ -s $token_file ]] || die 'run opencloud-upload setup first'
[[ -f $1 && -r $1 ]] || die 'expected a readable regular file'
file=$1
[[ $file == /* ]] || file="$PWD/$file"

# Curl reads the token from disk and prompts for the share password itself,
# keeping both credentials out of command-line arguments.
status=$(curl --disable --globoff --silent --show-error \
  --user public \
  --header 'X-Requested-With: XMLHttpRequest' \
  --variable "token@$token_file" \
  --variable "filename=${file##*/}" \
  --expand-url "$origin/remote.php/dav/public-files/{{token:trim:url}}/{{filename:url}}" \
  --upload-file "$file" \
  --output /dev/null --write-out '%{response_code}') || die 'transfer failed'

case $status in
  2??) printf 'Uploaded to the OpenCloud inbox: %s\n' "${file##*/}" ;;
  *) die "upload failed (HTTP $status); check the File Drop link and password" ;;
esac
