#!/bin/sh

set -euo pipefail

serverPubkey=$1
serverIP=$2
addr=$3
name=$4

# wg0 is split
# wg1 is full
# Add to network-manager with
# nmcli connection import type wireguard file wg0.conf
# nmcli connection import type wireguard file wg1.conf

mkdir -p $name

key=$(wg genkey)
pubKey=$(echo $key | wg pubkey)

echo "[Interface]
PrivateKey = $key
Address = 10.0.253.$addr/32
DNS = 1.1.1.1

[Peer]
PublicKey = $serverPubkey
Endpoint = $serverIP:51820
AllowedIPs = 10.0.0.1/32, 10.0.1.0/24
PersistentKeepalive = 25" \
  > "$name/wg0.conf"
echo $pubKey > "$name/$name-split.pub"

key=$(wg genkey)
pubKey=$(echo $key | wg pubkey)

echo "[Interface]
PrivateKey = $key
Address = 10.0.254.$addr/32
DNS = 1.1.1.1

[Peer]
PublicKey = $serverPubkey
Endpoint = $serverIP:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25" \
  > "$name/wg1.conf"
echo $pubKey > "$name/$name-full.pub"

echo Done

