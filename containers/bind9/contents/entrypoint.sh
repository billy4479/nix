#!/usr/bin/env sh
set -e

PUID="${PUID:-100}"
PGID="${PGID:-101}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Starting BIND with UID $PUID and GID $PGID..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Set UID/GID of bind user
sed -i "s/^bind\:x\:100\:101/bind\:x\:$PUID\:$PGID/" /etc/passwd
sed -i "s/^bind\:x\:101/bind\:x\:$PGID/" /etc/group

echo ""
exec $(command -v named) -u "bind" -g
