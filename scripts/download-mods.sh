#!/usr/bin/env bash
# Download the mods listed in $MODS_FILE from the official ModDB into $MODS_DIR,
# resolving each mod's dependencies (from its modinfo.json) recursively. Each line
# is a mod id, optionally pinned as "modid@version". Comments (#) and blank lines
# are ignored. Idempotent: unchanged mods are kept, removed ones pruned.
set -euo pipefail

MODS_FILE="${MODS_FILE:-/data/.mods.txt}"
MODS_DIR="${MODS_DIR:-/data/Mods}"
SERVER_DIR="${SERVER_DIR:-/data/.server}"
API="https://mods.vintagestory.at/api/mod"
STATE="${MODS_DIR}/.managed-mods.json"
CURL_OPTS=(-fsSL --connect-timeout 10 --retry 5 --retry-delay 3 --retry-connrefused --retry-all-errors)

log() { echo "[download-mods] $*"; }

mkdir -p "$MODS_DIR"

if [[ ! -f "$MODS_FILE" ]]; then
  log "No mods file at ${MODS_FILE}, skipping."
  exit 0
fi

GAME_VERSION="$(cat "${SERVER_DIR}/.vsversion" 2>/dev/null || echo "")"
GAME_MM="$(echo "$GAME_VERSION" | grep -oE '^[0-9]+\.[0-9]+' || true)"

[[ -f "$STATE" ]] || echo '{}' > "$STATE"
new_state="$(mktemp)"; echo '{}' > "$new_state"
keep_list="$(mktemp)"
trap 'rm -f "$new_state" "$keep_list"' EXIT

declare -A seen
queue=()
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="$(echo "${raw%%#*}" | xargs || true)"
  [[ -n "$line" ]] && queue+=("$line")
done < "$MODS_FILE"

errors=0
i=0
while (( i < ${#queue[@]} )); do
  entry="${queue[$i]}"; i=$((i+1))
  modid="${entry%@*}"; pin=""; [[ "$entry" == *"@"* ]] && pin="${entry#*@}"
  key="$(printf '%s' "$modid" | tr '[:upper:]' '[:lower:]')"
  [[ -n "${seen[$key]:-}" ]] && continue
  seen[$key]=1

  resp="$(curl "${CURL_OPTS[@]}" "${API}/${modid}" | tr -d '\000-\037' || true)"
  if [[ -z "$resp" ]] || [[ "$(printf '%s' "$resp" | jq -r '.statuscode')" != "200" ]]; then
    log "ERROR: mod '${modid}' not found on ModDB"; errors=$((errors+1)); continue
  fi

  release="$(printf '%s' "$resp" | jq -c \
    --arg pin "$pin" --arg gv "$GAME_VERSION" --arg gmm "$GAME_MM" '
    .mod.releases as $rels
    | if $pin != "" then ($rels | map(select(.modversion == $pin)) | .[0])
      else ( $rels | map(select(.tags | index($gv))) | .[0] )
        // ( $rels | map(select(.tags | map(startswith($gmm + ".")) | any)) | .[0] )
        // $rels[0] end')"
  if [[ -z "$release" || "$release" == "null" ]]; then
    log "ERROR: no matching release for '${modid}'${pin:+ @ ${pin}}"; errors=$((errors+1)); continue
  fi

  fileid="$(echo "$release" | jq -r '.fileid')"
  filename="$(echo "$release" | jq -r '.filename')"
  modver="$(echo "$release" | jq -r '.modversion')"
  dlurl="$(echo "$release" | jq -r '.mainfile')"
  target="${MODS_DIR}/${filename}"
  echo "$filename" >> "$keep_list"

  if [[ "$(jq -r --arg m "$key" '.[$m].fileid // empty' "$STATE")" == "$fileid" && -f "$target" ]]; then
    log "up-to-date: ${filename} (v${modver})"
  else
    log "downloading ${filename} (v${modver})"
    if curl "${CURL_OPTS[@]}" -o "${target}.part" "$dlurl"; then
      mv "${target}.part" "$target"
    else
      rm -f "${target}.part"; log "ERROR: download failed for '${modid}'"; errors=$((errors+1)); continue
    fi
  fi

  jq --arg m "$key" --arg f "$filename" --argjson id "$fileid" \
    '.[$m] = {filename:$f, fileid:$id}' "$new_state" > "${new_state}.tmp" && mv "${new_state}.tmp" "$new_state"

  # Queue dependencies declared in the mod's modinfo.json (skip the game itself).
  modinfo="$(unzip -p "$target" modinfo.json 2>/dev/null | tr -d '\000-\037' || true)"
  modinfo="${modinfo#$'\xEF\xBB\xBF'}"
  for dep in $(printf '%s' "$modinfo" | jq -r '(with_entries(.key|=ascii_downcase) | .dependencies // {}) | keys[]' 2>/dev/null || true); do
    dk="$(printf '%s' "$dep" | tr '[:upper:]' '[:lower:]')"
    [[ "$dk" == "game" || -n "${seen[$dk]:-}" ]] && continue
    log "dependency of ${modid}: ${dep}"
    queue+=("$dep")
  done
done

while IFS= read -r oldfile; do
  [[ -z "$oldfile" ]] && continue
  if ! grep -qxF "$oldfile" "$keep_list"; then
    log "removing stale mod: ${oldfile}"; rm -f "${MODS_DIR}/${oldfile}"
  fi
done < <(jq -r '.[].filename' "$STATE" 2>/dev/null || true)

cp "$new_state" "$STATE"
[[ "$errors" -gt 0 ]] && log "Finished with ${errors} error(s)." || log "All mods resolved."
