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

msg()  { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m?\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m✗\033[0m %s\n" "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v tar  >/dev/null 2>&1 || die "tar is required"

# Auth for private repos
CURL_AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  CURL_AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

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

msg "querying latest release..."
VERSION=$(curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
  "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" \
  | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)
[ -n "$VERSION" ] || die "could not resolve latest version (set GITHUB_TOKEN if the repo is private)"

VER_NUM="${VERSION#v}"
msg "latest version: $VERSION"

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

msg "downloading ${ARCHIVE}..."
curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" -o "$TMP/$ARCHIVE" "$ARCHIVE_URL" \
  || die "download failed: $ARCHIVE_URL (set GITHUB_TOKEN if the repo is private)"

msg "verifying checksum..."
curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" -o "$TMP/checksums.txt" "$CHECKSUMS_URL" \
  || die "download failed: $CHECKSUMS_URL"

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

msg "extracting..."
tar -xzf "$TMP/$ARCHIVE" -C "$TMP"

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
