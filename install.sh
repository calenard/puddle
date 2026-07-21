#!/usr/bin/env bash
#
# puddle installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/calenard/puddle/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/calenard/puddle/main/install.sh | bash -s -- v0.0.1 ~/bin
#
# Positional arguments:
#   $1  version    — release tag (e.g. v0.0.1). Defaults to "latest".
#   $2  prefix     — install directory. Defaults to the first writable
#                    directory in: /usr/local/bin, $HOME/.local/bin,
#                    $HOME/bin. Created if missing. Add it to your PATH
#                    if it isn't already.
#
# Environment overrides:
#   PUDDLE_VERSION    same as $1
#   PUDDLE_PREFIX     same as $2
#   GITHUB_TOKEN   personal access token — required while the repo is
#                  private, ignored once it goes public. Must have at
#                  least `contents:read` scope on the puddle repository.
#
# The script detects your OS and architecture, downloads the matching
# archive from the GitHub release, verifies the sha256 against the
# release's checksums.txt, extracts the binary, and moves it into the
# prefix directory. No sudo unless you explicitly pick a prefix that
# needs it.

set -euo pipefail

OWNER="calenard"
REPO="puddle"
BINARY="puddle"

VERSION="${1:-${PUDDLE_VERSION:-latest}}"
PREFIX="${2:-${PUDDLE_PREFIX:-}}"

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

# Trap to ensure spinner is stopped on exit
cleanup() {
  stop_spinner
}
trap cleanup EXIT INT TERM

# ---- detect OS + arch ----

uname_s=$(uname -s)
uname_m=$(uname -m)

case "$uname_s" in
  Linux)   OS=linux ;;
  Darwin)  OS=darwin ;;
  MINGW*|MSYS*|CYGWIN*)
    die "windows detected — use install.ps1 from powershell instead"
    ;;
  *) die "unsupported os: $uname_s" ;;
esac

case "$uname_m" in
  x86_64|amd64)         ARCH=amd64 ;;
  arm64|aarch64)        ARCH=arm64 ;;
  *) die "unsupported arch: $uname_m" ;;
esac

# ---- resolve version ----

if [ "$VERSION" = "latest" ]; then
  start_spinner "Querying latest release..."
  VERSION=""
  if [ ${#CURL_AUTH[@]} -gt 0 ]; then
    # Use API for private repos
    VERSION=$(curl -fsSL "${CURL_AUTH[@]+"${CURL_AUTH[@]}"}" \
      "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" \
      | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)
  else
    # For public repos, use redirect to get latest tag
    VERSION=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
      "https://github.com/${OWNER}/${REPO}/releases/latest" 2>/dev/null \
      | sed -E 's|.*/tag/([^/]+).*|\1|')
    # Fallback to API if redirect doesn't work
    if [ -z "$VERSION" ]; then
      VERSION=$(curl -fsSL "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" \
        | sed -nE 's/.*"tag_name": *"([^"]+)".*/\1/p' | head -n1)
    fi
  fi
  [ -n "$VERSION" ] || { stop_spinner; die "could not resolve latest version (set GITHUB_TOKEN if the repo is private)"; }
  stop_spinner
fi

case "$VERSION" in v*) ;; *) VERSION="v$VERSION" ;; esac
VER_NUM="${VERSION#v}"

msg "version: $VERSION"
msg "os/arch: ${OS}/${ARCH}"

# ---- pick an install prefix ----

pick_prefix() {
  local candidates=()
  [ -n "$PREFIX" ] && { echo "$PREFIX"; return; }
  candidates+=("/usr/local/bin")
  [ -n "${HOME:-}" ] && candidates+=("$HOME/.local/bin" "$HOME/bin")
  for d in "${candidates[@]}"; do
    if [ -d "$d" ] && [ -w "$d" ]; then
      echo "$d"
      return
    fi
  done
  # Nothing writable yet — create ~/.local/bin and use that.
  if [ -n "${HOME:-}" ]; then
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
    return
  fi
  die "no writable install prefix found; pass one as the second argument"
}

PREFIX=$(pick_prefix)
mkdir -p "$PREFIX"

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

# ---- install ----

msg "installing to $PREFIX/$BINARY"
install -m 0755 "$TMP/$BINARY" "$PREFIX/$BINARY" 2>/dev/null \
  || { cp "$TMP/$BINARY" "$PREFIX/$BINARY" && chmod 0755 "$PREFIX/$BINARY"; }

# ---- PATH hint ----

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    warn "$PREFIX is not on your PATH"
    warn "add this to your shell rc file:"
    warn "  export PATH=\"$PREFIX:\$PATH\""
    ;;
esac

msg "installed $("$PREFIX/$BINARY" --version 2>/dev/null || echo puddle)"
msg "run:  puddle          (interactive tui)"
msg "run:  puddle --help   (all flags and subcommands)"