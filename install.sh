#!/bin/sh
# Install (or upgrade, or remove) the Knwlge Enterprise Server.
#
#   curl -fsSL https://raw.githubusercontent.com/Replient/knwlge-releases/main/install.sh | sh
#
# Releases live in Replient/knwlge-releases, which two products share, so this script never
# trusts GitHub's "latest" release: it lists the releases, picks the newest stable
# `enterprise-v<version>` tag by SemVer, downloads that release's tarball for this machine
# (Linux or macOS, x64 or arm64; Rosetta is seen through) plus checksums.txt, verifies the
# SHA-256, and unpacks it into a versioned directory:
#
#   /opt/knwlge-enterprise/<version>            when run as root (or /opt/knwlge-enterprise is writable)
#   $HOME/.local/knwlge-enterprise/<version>    otherwise
#
# A `current` symlink next to it points at the installed version and `knwlge-enterprise` is
# linked into /usr/local/bin (root) or $HOME/.local/bin. Running the script again upgrades in
# place; the previously current version is kept so a service definition that names it keeps
# working until `knwlge-enterprise service install` is run again. Nothing outside those
# directories is touched — configuration stays in ~/.knwlge-enterprise (/etc/knwlge-enterprise).
#
# Options and environment:
#   --version <semver> | KNWLGE_ENTERPRISE_VERSION   install that release (pre-releases only this way)
#   --uninstall                                      remove the command, the install directory, nothing else
#   KNWLGE_ENTERPRISE_INSTALL_DIR                    install root instead of /opt/... or ~/.local/...
#   KNWLGE_ENTERPRISE_BIN_DIR                        where to link the command
#   KNWLGE_RELEASES_BASE_URL, KNWLGE_RELEASES_API_URL  mirror the release assets and the release list
#
# Requirements: curl, tar, and sha256sum or shasum.
set -eu

RELEASES_REPO="Replient/knwlge-releases"
RELEASES_API="${KNWLGE_RELEASES_API_URL:-https://api.github.com/repos/${RELEASES_REPO}/releases?per_page=100}"
DOWNLOAD_BASE="${KNWLGE_RELEASES_BASE_URL:-https://github.com/${RELEASES_REPO}/releases/download}"
TAG_PREFIX="enterprise-v"
COMMAND="knwlge-enterprise"

log() { printf '%s\n' "$*" >&2; }
fail() {
  log "install.sh: $*"
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required but was not found on PATH."
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

# linux|darwin
detect_os() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo darwin ;;
    *) fail "unsupported operating system $(uname -s); Linux and macOS are supported." ;;
  esac
}

# x64|arm64 — on macOS a shell under Rosetta reports x86_64, so ask the kernel.
detect_arch() {
  machine="$(uname -m)"
  if [ "$(uname -s)" = Darwin ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    machine=arm64
  fi
  case "$machine" in
    x86_64 | amd64) echo x64 ;;
    aarch64 | arm64) echo arm64 ;;
    *) fail "unsupported CPU architecture ${machine}; x64 and arm64 are supported." ;;
  esac
}

# Newest stable `enterprise-v<version>` by SemVer. Only tag names are read from the release
# list (no jq: the JSON is split on commas so every "tag_name" pair lands on a line of its own).
newest_stable_version() {
  curl -fsSL -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$RELEASES_API" |
    tr -d '\r' | tr ',' '\n' |
    sed -n 's/^.*"tag_name"[[:space:]]*:[[:space:]]*"'"$TAG_PREFIX"'\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*$/\1/p' |
    sort -t . -k 1,1n -k 2,2n -k 3,3n |
    tail -n 1
}

is_root() { [ "$(id -u)" = 0 ]; }

install_root() {
  if [ -n "${KNWLGE_ENTERPRISE_INSTALL_DIR:-}" ]; then
    echo "$KNWLGE_ENTERPRISE_INSTALL_DIR"
  elif [ -d /opt/knwlge-enterprise ] && [ -w /opt/knwlge-enterprise ]; then
    echo /opt/knwlge-enterprise
  elif is_root; then
    echo /opt/knwlge-enterprise
  else
    echo "${HOME}/.local/knwlge-enterprise"
  fi
}

bin_dir() {
  if [ -n "${KNWLGE_ENTERPRISE_BIN_DIR:-}" ]; then
    echo "$KNWLGE_ENTERPRISE_BIN_DIR"
  elif [ "$1" = /opt/knwlge-enterprise ]; then
    echo /usr/local/bin
  else
    echo "${HOME}/.local/bin"
  fi
}

on_path() {
  case ":${PATH}:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# -n keeps ln from following an existing link to a directory (GNU, BSD/macOS and BusyBox all
# accept it; a plain `mv` over such a link would move the new link inside the directory).
replace_symlink() {
  target="$1"
  link="$2"
  ln -sfn "$target" "$link"
  [ "$(readlink "$link")" = "$target" ] || fail "could not point ${link} at ${target}."
}

service_hint() {
  for unit in /etc/systemd/system/knwlge-enterprise.service \
    "${HOME}/.config/systemd/user/knwlge-enterprise.service" \
    "${HOME}/Library/LaunchAgents/com.knwlge.enterprise.plist"; do
    if [ -f "$unit" ]; then
      log "A service definition exists at ${unit}: run \`${COMMAND} service install\` again so it points at ${1}, then restart the service."
      return 0
    fi
  done
  return 0
}

install_release() {
  version="$1"
  os="$(detect_os)"
  arch="$(detect_arch)"
  tag="${TAG_PREFIX}${version}"
  name="${COMMAND}-${version}-${os}-${arch}"
  asset="${name}.tar.gz"
  root="$(install_root)"
  bindir="$(bin_dir "$root")"

  workdir="$(mktemp -d "${TMPDIR:-/tmp}/knwlge-enterprise-install.XXXXXX")"
  trap 'rm -rf "$workdir"' EXIT INT TERM

  log "Downloading ${asset} from ${RELEASES_REPO} ${tag}…"
  curl -fsSL -o "${workdir}/${asset}" "${DOWNLOAD_BASE}/${tag}/${asset}"
  curl -fsSL -o "${workdir}/checksums.txt" "${DOWNLOAD_BASE}/${tag}/checksums.txt"

  expected="$(awk -v name="$asset" '$2 == name || $2 == "*" name {print $1}' "${workdir}/checksums.txt" | head -n 1)"
  [ -n "$expected" ] || fail "checksums.txt in ${tag} does not list ${asset}."
  actual="$(sha256_of "${workdir}/${asset}")"
  [ "$expected" = "$actual" ] || fail "SHA-256 mismatch for ${asset}: expected ${expected}, got ${actual}."

  log "Installing ${COMMAND} ${version} into ${root}/${version}…"
  mkdir -p "$root" || fail "cannot create ${root} (run as root for /opt, or set KNWLGE_ENTERPRISE_INSTALL_DIR)."
  [ -w "$root" ] || fail "${root} is not writable (run as root, or set KNWLGE_ENTERPRISE_INSTALL_DIR)."
  tar -xzf "${workdir}/${asset}" -C "$workdir"
  [ -x "${workdir}/${name}/bin/${COMMAND}" ] || fail "${asset} does not contain ${name}/bin/${COMMAND}."
  rm -rf "${root:?}/.staging-${version:?}" "${root:?}/${version:?}"
  mv "${workdir}/${name}" "${root}/.staging-${version}"
  mv "${root}/.staging-${version}" "${root}/${version}"

  previous=""
  if [ -L "${root}/current" ]; then
    previous="$(basename "$(readlink "${root}/current")")"
  fi
  replace_symlink "$version" "${root}/current"

  # On an upgrade, keep the previously current version (a service unit may still name it) and
  # drop anything older. A re-install of the same version leaves the other directories alone.
  if [ -n "$previous" ] && [ "$previous" != "$version" ]; then
    for dir in "$root"/*/; do
      dir="${dir%/}"
      old="$(basename "$dir")"
      case "$old" in
        "$version" | "$previous" | current) continue ;;
      esac
      if [ -d "$dir" ] && [ ! -L "$dir" ]; then
        rm -rf "$dir"
        log "Removed older version ${old}"
      fi
    done
  fi

  mkdir -p "$bindir" || fail "cannot create ${bindir} (set KNWLGE_ENTERPRISE_BIN_DIR)."
  if [ -w "$bindir" ]; then
    replace_symlink "${root}/current/bin/${COMMAND}" "${bindir}/${COMMAND}"
    linked="${bindir}/${COMMAND}"
  else
    linked=""
    log "${bindir} is not writable; the command is at ${root}/current/bin/${COMMAND}. Link it yourself, e.g."
    log "  sudo ln -sf ${root}/current/bin/${COMMAND} ${bindir}/${COMMAND}"
  fi

  installed="$("${root}/current/bin/${COMMAND}" --version 2>/dev/null || true)"
  [ "$installed" = "$version" ] || fail "${root}/current/bin/${COMMAND} --version printed \"${installed}\", not ${version}."

  if [ -n "$previous" ] && [ "$previous" != "$version" ]; then
    log "${COMMAND} ${version} installed (was ${previous})."
    service_hint "$version"
  else
    log "${COMMAND} ${version} installed."
  fi
  if [ -n "$linked" ] && ! on_path "$bindir"; then
    log "Add ${bindir} to PATH, e.g.:  export PATH=\"${bindir}:\$PATH\""
  fi
  log "Next: ${COMMAND} setup"
}

remove_link_if_ours() {
  link="$1"
  [ -L "$link" ] || return 0
  case "$(readlink "$link")" in
    */knwlge-enterprise/current/bin/${COMMAND} | "${KNWLGE_ENTERPRISE_INSTALL_DIR:-/nonexistent}/current/bin/${COMMAND}")
      rm -f "$link"
      log "Removed ${link}"
      ;;
  esac
}

uninstall() {
  for root in "${KNWLGE_ENTERPRISE_INSTALL_DIR:-}" /opt/knwlge-enterprise "${HOME}/.local/knwlge-enterprise"; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    if [ -w "$root" ] && [ -w "$(dirname "$root")" ]; then
      rm -rf "$root"
      log "Removed ${root}"
    else
      log "Cannot remove ${root} (not writable); run as root."
    fi
  done
  for link in "${KNWLGE_ENTERPRISE_BIN_DIR:-}/${COMMAND}" "/usr/local/bin/${COMMAND}" "${HOME}/.local/bin/${COMMAND}"; do
    case "$link" in /*) remove_link_if_ours "$link" ;; esac
  done
  log "Configuration and data under ~/.knwlge-enterprise (or /etc/knwlge-enterprise) were left in place."
}

usage() {
  cat >&2 <<EOF
Usage: install.sh [--version <semver>] [--uninstall]

Installs the newest stable Knwlge Enterprise Server release (or the given version) into
/opt/knwlge-enterprise/<version> as root, else \$HOME/.local/knwlge-enterprise/<version>, and
links ${COMMAND} into /usr/local/bin or \$HOME/.local/bin. Run again to upgrade.

  --version <semver>   install that release (also KNWLGE_ENTERPRISE_VERSION); pre-releases only this way
  --uninstall          remove the command and the install directory; configuration is kept

Environment: KNWLGE_ENTERPRISE_INSTALL_DIR, KNWLGE_ENTERPRISE_BIN_DIR, KNWLGE_RELEASES_BASE_URL,
KNWLGE_RELEASES_API_URL. Docs: https://github.com/${RELEASES_REPO}
EOF
}

main() {
  version="${KNWLGE_ENTERPRISE_VERSION:-}"
  action=install
  while [ $# -gt 0 ]; do
    case "$1" in
      --uninstall) action=uninstall ;;
      --version)
        [ $# -ge 2 ] || fail "--version needs a value."
        version="$2"
        shift
        ;;
      --version=*) version="${1#--version=}" ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) fail "unknown option $1 (see --help)." ;;
    esac
    shift
  done

  if [ "$action" = uninstall ]; then
    uninstall
    return 0
  fi

  need_command curl
  need_command tar
  if [ -z "$version" ]; then
    version="$(newest_stable_version)"
    [ -n "$version" ] || fail "no stable ${TAG_PREFIX}* release was found in ${RELEASES_REPO}."
  fi
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "version must look like 1.2.3 (got \"${version}\")." ;;
  esac
  install_release "$version"
}

main "$@"
