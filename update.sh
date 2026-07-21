#!/usr/bin/env bash
#
# puddle updater — download and install the latest release, then run a command.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/calenard/puddle/main/update.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/calenard/puddle/main/update.sh | bash -s -- "puddle --help"
#
# Positional arguments:
#   $1  command    — command to run after update. Defaults to "puddle".
#
# Environment overrides:
#   GITHUB_TOKEN   personal access token — required while the repo is
#                  private. Must have at least `contents:read` scope.

set -euo pipefail

OWNER="calenard"
REPO="puddle"
BINARY="puddle"

CMD="${1:-puddle}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

msg()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}?${NC} %s\n" "$*" >&2; }
die()  { printf "${RED}✗${NC} %s\n" "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"

# Auth for private repos
CURL_AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

# Spinner animation
SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin_pid=0

start_spinner() {
  local msg="$1"
  printf "${CYAN}${SPINNER[0]}${NC} %s" "$msg"
  (
    i=0
    while true; do
      printf "\r${CYAN}${SPINNER[i]}${NC} %s" "$msg"
      i=$(( (i + 1) % ${#SPINNER[@]} ))
      sleep 0.1
    done
  ) &
  spin_pid=$!
}

stop_spinner() {
  if [ $spin_pid -ne 0 ]; then
    kill $spin_pid 2>/dev/null
    wait $spin_pid 2>/dev/null
    spin_pid=0
  fi
  printf "\r\033[K"
}

# ---- detect OS + arch ----

uname_s=$(uname -s)
uname_m=$(uname -m)

case "$uname_s" in
  Linux)   OS=linux ;;
  Darwin)  OS=darwin ;;
  MINGW*|MSYS*|CYGWIN*)
    die "windows detected — use update.ps1 from powershell instead"
    ;;
  *) die "unsupported os: $uname_s" ;;
esac

case "$uname_m" in
  x86_64|amd64)         ARCH=amd64 ;;
  arm64|aarch64)        ARCH=arm64 ;;
  *) die "unsupported arch: $uname_m" ;;
esac

# ---- resolve latest version ----

start_spinner "Querying latest release..."
VERSION=$(curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
  "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" \
  | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)
[ -n "$VERSION" ] || { stop_spinner; die "could not resolve latest version (set GITHUB_TOKEN if the repo is private)"; }
stop_spinner
msg "latest version: $VERSION"

VER_NUM="${VERSION#v}"

# ---- find current binary ----

CURRENT_BIN=""
if command -v "$BINARY" >/dev/null 2>&1; then
  CURRENT_BIN=$(command -v "$BINARY")
elif [ -x "./$BINARY" ]; then
  CURRENT_BIN="./$BINARY"
else
  die "'$BINARY' not found in PATH or current directory"
fi

CURRENT_VER=""
if [ -n "$CURRENT_BIN" ]; then
  CURRENT_VER=$("$CURRENT_BIN" --version 2>/dev/null | head -n1 || true)
fi
msg "current: ${CURRENT_VER:-unknown}"
msg "target:  $VERSION"

# ---- download + verify + extract ----

ARCHIVE="${BINARY}_${VER_NUM}_${OS}_${ARCH}.tar.gz"
BASE_URL="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION}"
ARCHIVE_URL="${BASE_URL}/${ARCHIVE}"
CHECKSUMS_URL="${BASE_URL}/checksums.txt"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

start_spinner "Downloading ${ARCHIVE}"
curl -fL# "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" -o "$TMP/$ARCHIVE" "$ARCHIVE_URL" \
  || { stop_spinner; die "download failed: $ARCHIVE_URL (set GITHUB_TOKEN if the repo is private)"; }
stop_spinner
msg "downloaded ${ARCHIVE}"

start_spinner "Verifying checksum"
curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" -o "$TMP/checksums.txt" "$CHECKSUMS_URL" \
  || { stop_spinner; die "download failed: $CHECKSUMS_URL"; }
stop_spinner

expected=$(grep " ${ARCHIVE}\$" "$TMP/checksums.txt" | awk '{print $1}' || true)
[ -n "$expected" ] || die "no checksum for $ARCHIVE in checksums.txt"

if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$TMP/$ARCHIVE" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$TMP/$ARCHIVE" | awk '{print $1}')
else
  die "no sha256 tool found (sha256sum or shasum)"
fi

[ "$expected" = "$actual" ] \
  || die "checksum mismatch: expected $expected, got $actual"
msg "checksum verified"

start_spinner "Extracting"
tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
stop_spinner

[ -f "$TMP/$BINARY" ] || die "archive did not contain a '$BINARY' binary"

# ---- replace binary ----

# Resolve symlinks
RESOLVED=$(readlink -f "$CURRENT_BIN" 2>/dev/null || echo "$CURRENT_BIN")
DIR=$(dirname "$RESOLVED")

msg "updating $RESOLVED..."
install -m 0755 "$TMP/$BINARY" "$RESOLVED" 2>/dev/null \
  || { cp "$TMP/$BINARY" "$RESOLVED" && chmod 0755 "$RESOLVED"; }

msg "puddle $VERSION installed successfully"

# ---- run command ----

if [ -n "$CMD" ]; then
  msg "running: $CMD"
  exec $CMD
fi