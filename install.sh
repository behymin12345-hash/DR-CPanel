#!/usr/bin/env bash
set -euo pipefail

REPO="behymin12345-hash/DR-CPanel"
BRANCH="main"
URL="https://raw.githubusercontent.com/$REPO/$BRANCH/dr-cpanel.sh"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }

curl -fsSL "$URL" -o /usr/local/bin/dr-cpanel
chmod +x /usr/local/bin/dr-cpanel
exec /usr/local/bin/dr-cpanel
