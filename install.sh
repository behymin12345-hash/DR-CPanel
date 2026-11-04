#!/usr/bin/env bash
# DR-CPanel installer / updater
# Usage:  bash <(curl -fsSL https://raw.githubusercontent.com/behymin12345-hash/DR-CPanel/main/install.sh)
set -euo pipefail

REPO="behymin12345-hash/DR-CPanel"
BRANCH="main"
URL="https://raw.githubusercontent.com/$REPO/$BRANCH/dr-cpanel.sh"
BIN="/usr/local/bin/dr-cpanel"

G='\033[1;32m'; Y='\033[1;33m'; C='\033[1;36m'; R='\033[1;31m'; B='\033[1m'; N='\033[0m'
ok()  { echo -e "  ${G}✔${N} $*"; }
err() { echo -e "  ${R}✘${N} $*"; }
info(){ echo -e "  ${C}•${N} $*"; }

echo -e "${C}${B}"
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │   DR-CPanel  installer  ·  port-forward manager   │"
echo "  │   by @DR_Gojo_Satoruu  (t.me/DR_Gojo_Satoruu)     │"
echo "  └──────────────────────────────────────────────────┘${N}"
echo

[[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }

# ---- curl (install if missing) --------------------------------------------
if ! command -v curl >/dev/null 2>&1; then
  info "curl not found, installing..."
  if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq curl
  elif command -v dnf >/dev/null 2>&1; then dnf install -y curl
  elif command -v yum >/dev/null 2>&1; then yum install -y curl
  fi
  command -v curl >/dev/null 2>&1 || { err "Could not install curl."; exit 1; }
fi

# ---- download to a temp file first (never break an installed binary) ------
TMP="$(mktemp)"
info "Downloading dr-cpanel from github.com/$REPO ..."
if ! curl -fsSL --retry 3 --retry-delay 2 "$URL" -o "$TMP"; then
  err "Download failed."
  info "If GitHub is blocked on this server, download dr-cpanel.sh manually,"
  info "then run:  install -m 755 dr-cpanel.sh $BIN && $BIN"
  rm -f "$TMP"; exit 1
fi

# ---- validate what we downloaded ------------------------------------------
if [[ ! -s $TMP ]] || ! head -1 "$TMP" | grep -q "usr/bin/env bash" || ! grep -q 'VERSION="' "$TMP"; then
  err "Downloaded file is not a valid DR-CPanel script (blocked or empty?)."
  rm -f "$TMP"; exit 1
fi
VER="$(grep -m1 'VERSION="' "$TMP" | sed 's/.*VERSION="\([^"]*\)".*/\1/')"

# ---- fresh install or update? ---------------------------------------------
MODE="install"
[[ -x $BIN ]] && MODE="update"

install -m 755 "$TMP" "$BIN"
rm -f "$TMP"
ok "v$VER saved to $BIN"

if [[ $MODE == update ]]; then
  ok "Updated (existing tunnels and settings in /etc/dr-cpanel are kept)."
else
  ok "Installed."
  echo
  info "Open the menu any time with:  dr-cpanel"
  info "Web panel: menu → 9) Web panel → 1) Install / update"
fi

echo
echo -e "  ${G}${B}Done. Starting DR-CPanel v$VER ...${N}"
echo
sleep 1
exec "$BIN"
