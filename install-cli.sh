#!/bin/sh
# Install the newest `knwlge` developer CLI release.
#
#   curl -fsSL https://raw.githubusercontent.com/Replient/knwlge-releases/main/install-cli.sh | sh
#
# Releases live in Replient/knwlge-releases, which two products share, so this
# script never trusts GitHub's "latest" release: it lists the releases, picks
# the newest tag that starts with `cli-v`, downloads that release's
# `knwlge-<version>.tgz` plus `checksums.txt`, verifies the SHA-256, and installs
# the tarball with `npm install -g`. Set KNWLGE_CLI_VERSION=1.2.3 to install a
# specific version instead of the newest one.
#
# Requirements: Node.js 22 or newer on PATH (with npm), curl, and either
# sha256sum or shasum.
set -eu

RELEASES_REPO="Replient/knwlge-releases"
RELEASES_API="https://api.github.com/repos/${RELEASES_REPO}/releases?per_page=100"
DOWNLOAD_BASE="https://github.com/${RELEASES_REPO}/releases/download"
TAG_PREFIX="cli-v"
MIN_NODE_MAJOR=22

log() { printf '%s\n' "$*" >&2; }
fail() {
  log "install-cli: $*"
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required but was not found on PATH."
}

node_install_hint() {
  cat >&2 <<'EOF'
knwlge needs Node.js 22 or newer on PATH (the persistent sidecar service pins the
exact Node executable it was installed with, so use a durable install, not a
temporary shell-only runtime):

  macOS:   brew install node@22
  Linux:   https://nodejs.org/en/download/package-manager
  Windows: https://nodejs.org/en/download (then run this script from Git Bash or WSL)

Re-run this script after `node --version` reports v22 or newer.
EOF
}

check_node() {
  if ! command -v node >/dev/null 2>&1; then
    node_install_hint
    fail "Node.js was not found on PATH."
  fi
  node_version="$(node --version 2>/dev/null || true)"
  node_major="$(printf '%s' "$node_version" | sed -n 's/^v\([0-9][0-9]*\)\..*$/\1/p')"
  if [ -z "$node_major" ] || [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
    node_install_hint
    fail "Node.js ${MIN_NODE_MAJOR} or newer is required; found ${node_version:-unknown}."
  fi
  need_command npm
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required to verify the download."
  fi
}

# Newest `cli-v<version>` tag by SemVer order (pre-releases sort below their
# final release). Only tag names are read from the API response.
newest_cli_tag() {
  curl -fsSL -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$RELEASES_API" |
    tr -d '\r' |
    sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\('"$TAG_PREFIX"'[0-9A-Za-z.+-]*\)".*$/\1/p' |
    sed 's/^'"$TAG_PREFIX"'//' |
    awk -F'[.-]' '{
      pre = (index($0, "-") > 0) ? 0 : 1
      printf "%09d.%09d.%09d.%d %s\n", $1, $2, $3, pre, $0
    }' |
    sort -r |
    head -n 1 |
    awk '{print $2}'
}

main() {
  need_command curl
  check_node

  version="${KNWLGE_CLI_VERSION:-}"
  if [ -z "$version" ]; then
    version="$(newest_cli_tag)"
    [ -n "$version" ] || fail "No ${TAG_PREFIX}* release was found in ${RELEASES_REPO}."
  fi
  tag="${TAG_PREFIX}${version}"
  asset="knwlge-${version}.tgz"

  workdir="$(mktemp -d "${TMPDIR:-/tmp}/knwlge-install.XXXXXX")"
  trap 'rm -rf "$workdir"' EXIT INT TERM

  log "Downloading ${asset} from ${RELEASES_REPO} ${tag}…"
  curl -fsSL -o "${workdir}/${asset}" "${DOWNLOAD_BASE}/${tag}/${asset}"
  curl -fsSL -o "${workdir}/checksums.txt" "${DOWNLOAD_BASE}/${tag}/checksums.txt"

  expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "${workdir}/checksums.txt" | head -n 1)"
  [ -n "$expected" ] || fail "checksums.txt in ${tag} does not list ${asset}."
  actual="$(sha256_of "${workdir}/${asset}")"
  [ "$expected" = "$actual" ] || fail "SHA-256 mismatch for ${asset}: expected ${expected}, got ${actual}."

  log "Installing knwlge ${version} with npm…"
  npm install -g --no-audit --no-fund "${workdir}/${asset}"

  installed="$(knwlge --version 2>/dev/null || true)"
  if [ "$installed" != "$version" ]; then
    log "knwlge ${version} was installed, but \`knwlge --version\` printed \"${installed}\"."
    log "Make sure npm's global bin directory ($(npm prefix -g)/bin) is on PATH."
    exit 1
  fi
  log "knwlge ${version} installed. Next: knwlge init --api-url https://your-enterprise-server"
}

main "$@"
