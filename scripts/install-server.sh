#!/usr/bin/env bash
# Resolve the desired Vintage Story server version and install it into $SERVER_DIR.
# Downloads only when the version differs from the installed one, and falls back
# to the installed version if the network is unreachable.
set -euo pipefail

VS_CHANNEL="${VS_CHANNEL:-stable}"
VS_VERSION="${VS_VERSION:-}"
SERVER_DIR="${SERVER_DIR:-/data/.server}"
API_BASE="https://api.vintagestory.at"
CDN_BASE="https://cdn.vintagestory.at/gamefiles"
CURL_OPTS=(-fsSL --connect-timeout 10 --retry 5 --retry-delay 3 --retry-connrefused --retry-all-errors)

log() { echo "[install-server] $*"; }

case "$VS_CHANNEL" in
  stable|unstable) ;;
  *) log "ERROR: VS_CHANNEL must be 'stable' or 'unstable' (got '$VS_CHANNEL')"; exit 1 ;;
esac

installed=""
if [[ -f "${SERVER_DIR}/.vsversion" && -f "${SERVER_DIR}/VintagestoryServer.dll" ]]; then
  installed="$(cat "${SERVER_DIR}/.vsversion")"
fi

if [[ -n "$VS_VERSION" ]]; then
  desired="$VS_VERSION"
  log "Requested version: ${desired} (${VS_CHANNEL})"
else
  log "Resolving latest ${VS_CHANNEL} version..."
  if desired="$(curl "${CURL_OPTS[@]}" "${API_BASE}/latest${VS_CHANNEL}.txt" | tr -d '[:space:]')" \
       && [[ -n "$desired" ]]; then
    log "Latest ${VS_CHANNEL}: ${desired}"
  elif [[ -n "$installed" ]]; then
    log "Version API unreachable, keeping installed ${installed}."
    exit 0
  else
    log "ERROR: cannot resolve a version and nothing is installed yet."
    exit 1
  fi
fi

if [[ "$installed" == "$desired" ]]; then
  log "Version ${desired} already installed."
  exit 0
fi

tarball="vs_server_linux-x64_${desired}.tar.gz"
url="${CDN_BASE}/${VS_CHANNEL}/${tarball}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

log "Downloading ${url}"
if ! curl "${CURL_OPTS[@]}" -o "${tmp}/${tarball}" "$url"; then
  if [[ -n "$installed" ]]; then
    log "Download failed, keeping installed ${installed}."
    exit 0
  fi
  log "ERROR: download failed for version '${desired}' (${VS_CHANNEL})."
  exit 1
fi

rm -rf "${SERVER_DIR}"
mkdir -p "${SERVER_DIR}"
tar -xzf "${tmp}/${tarball}" -C "${SERVER_DIR}"
[[ -f "${SERVER_DIR}/VintagestoryServer.dll" ]] || { log "ERROR: extraction incomplete."; exit 1; }
echo "$desired" > "${SERVER_DIR}/.vsversion"
log "Installed Vintage Story server ${desired}."

rc="${SERVER_DIR}/VintagestoryServer.runtimeconfig.json"
if [[ -f "$rc" ]]; then
  need="$(grep -oE '"version":[[:space:]]*"[0-9]+' "$rc" | grep -oE '[0-9]+$' | head -1 || true)"
  have="$(dotnet --list-runtimes 2>/dev/null | grep -oE 'Microsoft.NETCore.App [0-9]+' | grep -oE '[0-9]+$' | sort -rn | head -1 || true)"
  if [[ -n "$need" && -n "$have" && "$need" != "$have" ]]; then
    log "WARNING: server needs .NET ${need} but image ships .NET ${have} — use the matching image tag."
  fi
fi
