#!/usr/bin/env bash
# Prepare data dir and permissions, build the mod list from VS_MODS, install the
# server, download mods, apply serverconfig overrides from env, then run the
# server as a non-root user.
set -euo pipefail

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
DATA_DIR="${DATA_DIR:-/data}"
SERVER_DIR="${SERVER_DIR:-${DATA_DIR}/.server}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
export SERVER_DIR
export MODS_DIR="${DATA_DIR}/Mods"

log() { echo "[entrypoint] $*"; }

mkdir -p "${DATA_DIR}" "${DATA_DIR}/Saves" "${DATA_DIR}/Mods"

RUN_AS=()
if [[ "$(id -u)" == "0" ]]; then
  groupmod -o -g "$PGID" vintagestory 2>/dev/null || groupadd -o -g "$PGID" vintagestory
  usermod  -o -u "$PUID" -g "$PGID" vintagestory 2>/dev/null || true
  log "Running as uid=${PUID} gid=${PGID}"
  chown -R "${PUID}:${PGID}" "${DATA_DIR}" /home/vintagestory || true
  export HOME=/home/vintagestory
  RUN_AS=(gosu "${PUID}:${PGID}")
fi

# Build the mod list from VS_MODS (newline/space/comma separated).
EFFECTIVE_MODS="${DATA_DIR}/.mods.txt"
rm -f "$EFFECTIVE_MODS"
if [[ -n "${VS_MODS:-}" ]]; then
  printf '%s\n' "$VS_MODS" | tr ', ' '\n\n' > "$EFFECTIVE_MODS"
  chown "${PUID}:${PGID}" "$EFFECTIVE_MODS" 2>/dev/null || true
  log "Mod list: $(grep -cvE '^\s*$' "$EFFECTIVE_MODS") entr(y/ies) from VS_MODS"
fi
export MODS_FILE="$EFFECTIVE_MODS"

"${RUN_AS[@]}" /app/scripts/install-server.sh
"${RUN_AS[@]}" /app/scripts/download-mods.sh

for var in VS_WHITELIST_MODE VS_MAX_CLIENTS; do
  val="${!var:-}"
  if [[ -n "$val" && ! "$val" =~ ^[0-9]+$ ]]; then
    log "WARNING: ${var}='${val}' is not a number, ignoring."
    printf -v "$var" '%s' ''
  fi
done

setconfig="$(jq -nc \
  --arg whitelist "${VS_WHITELIST_MODE:-}" --arg name "${VS_SERVER_NAME:-}" \
  --arg maxc "${VS_MAX_CLIENTS:-}" --arg pass "${VS_PASSWORD:-}" --arg motd "${VS_MOTD:-}" \
  '{}
   | (if $whitelist != "" then .WhitelistMode = ($whitelist|tonumber) else . end)
   | (if $name      != "" then .ServerName    = $name            else . end)
   | (if $maxc      != "" then .MaxClients     = ($maxc|tonumber) else . end)
   | (if $pass      != "" then .Password       = $pass           else . end)
   | (if $motd      != "" then .WelcomeMessage = $motd           else . end)')"

cd "$SERVER_DIR"

# --setconfig writes the values and exits, so run it before starting the server.
if [[ -n "$setconfig" && "$setconfig" != "{}" ]]; then
  log "Applying serverconfig overrides: ${setconfig}"
  "${RUN_AS[@]}" dotnet "${SERVER_DIR}/VintagestoryServer.dll" \
    --dataPath "$DATA_DIR" "--setconfig=${setconfig}" || true
fi

log "Starting Vintage Story server"
# shellcheck disable=SC2086
exec "${RUN_AS[@]}" dotnet "${SERVER_DIR}/VintagestoryServer.dll" \
  --dataPath "$DATA_DIR" $EXTRA_ARGS "$@"
