#!/usr/bin/env bash
# Decode VS_CONFIG_TOKEN (from the VS-Config-Generator) and merge it into
# serverconfig.json before the server starts. Only re-applies when the token
# changed (hashed under /data), so manual edits survive unchanged restarts.
# On any decode/parse error it warns and skips (never blocks the server).
set -euo pipefail

TOKEN="${VS_CONFIG_TOKEN:-}"
DATA_DIR="${DATA_DIR:-/data}"
CFG="${DATA_DIR}/serverconfig.json"
HASHFILE="${DATA_DIR}/.config-token.hash"

log() { echo "[config-token] $*"; }

[[ -z "$TOKEN" ]] && exit 0

ver="${TOKEN%%.*}"
if [[ "$ver" != "v2" && "$ver" != "v3" ]] || [[ "${TOKEN#*.}" == "$TOKEN" ]]; then
  log "WARNING: token is not 'v2.<payload>' or 'v3.<payload>', skipping."; exit 0
fi
# Decode base64url (+ raw DEFLATE for v3). Raw DEFLATE has no zlib/gzip header, so
# this needs a zlib raw-inflate (Python stdlib), not gunzip/unzip.
payload="$(VS_TOKEN="$TOKEN" python3 - <<'PY' 2>/dev/null || true
import os, sys, base64, zlib
tok = (os.environ.get("VS_TOKEN") or "").strip()
ver, _, pl = tok.partition(".")
pl += "=" * (-len(pl) % 4)
try:
    raw = base64.urlsafe_b64decode(pl.encode())
    if ver == "v3":
        raw = zlib.decompress(raw, -15)
    sys.stdout.write(raw.decode("utf-8"))
except Exception:
    sys.exit(1)
PY
)"
if [[ -z "$payload" ]] || ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
  log "WARNING: token payload could not be decoded, skipping."; exit 0
fi

# World-gen settings (PlayStyle, Seed, WorldConfiguration, map height) are only
# read by VS when a NEW world is created. If a save already exists, VS loads its
# baked-in settings and ignores serverconfig.json's WorldConfig — so a token that
# carries world settings will write them to the file but NOT change the live
# world. Warn loudly so this isn't silent. (Server settings like name/slots/PvP
# are not save-bound and apply normally.) Re-checked every start, even when the
# token is unchanged below.
has_world="$(printf '%s' "$payload" | jq -r \
  '((.world // {} | length) > 0) or ((.worldConfiguration // {} | length) > 0)' 2>/dev/null || echo false)"
if [[ "$has_world" == "true" ]] && compgen -G "${DATA_DIR}/Saves/*.vcdbs" >/dev/null 2>&1; then
  log "WARNING: a world already exists in ${DATA_DIR}/Saves."
  log "         The token's world-gen settings (PlayStyle, Seed, WorldConfiguration,"
  log "         map height) only apply when a NEW world is created and were NOT applied"
  log "         to the existing world. Delete ${DATA_DIR}/Saves to regenerate with them."
  log "         (Server settings such as name, slots and PvP were applied normally.)"
fi

newhash="$(printf '%s' "$TOKEN" | sha256sum | cut -d' ' -f1)"
if [[ -f "$HASHFILE" && "$(cat "$HASHFILE" 2>/dev/null)" == "$newhash" ]]; then
  log "Token unchanged, skipping (existing config kept)."
  exit 0
fi

base="{}"; [[ -f "$CFG" ]] && base="$(cat "$CFG" 2>/dev/null || echo '{}')"
printf '%s' "$base" | jq -e . >/dev/null 2>&1 || base="{}"

# Block-wise merge; empty/absent blocks are skipped. Env (VS_*) is applied after
# this step (via --setconfig) and therefore wins on overlapping keys.
merged="$(jq -n --argjson cfg "$base" --argjson p "$payload" '
  $cfg
  | (if ($p.worldConfiguration // {} | length) > 0
       then .WorldConfig.WorldConfiguration = $p.worldConfiguration else . end)
  | (if $p.world.WorldName != null then .WorldConfig.WorldName = $p.world.WorldName else . end)
  | (if $p.world.Seed      != null then .WorldConfig.Seed      = $p.world.Seed      else . end)
  | (if ($p.world.PlayStyle // "") != ""
       then .WorldConfig.PlayStyle = $p.world.PlayStyle
          | .WorldConfig.PlayStyleLangCode = $p.world.PlayStyle else . end)
  | (if $p.world.MapSizeY  != null
       then .WorldConfig.MapSizeY = $p.world.MapSizeY | .MapSizeY = $p.world.MapSizeY else . end)
  | reduce (($p.server // {}) | to_entries[]) as $e (.; .[$e.key] = $e.value)
  | (if ($p.roles // null) != null then .Roles = $p.roles else . end)
  | (if ($p.defaultRoleCode // null) != null then .DefaultRoleCode = $p.defaultRoleCode else . end)
' 2>/dev/null || true)"

if [[ -z "$merged" ]] || ! printf '%s' "$merged" | jq -e . >/dev/null 2>&1; then
  log "WARNING: merge produced invalid JSON, skipping."; exit 0
fi

printf '%s\n' "$merged" | jq . > "${CFG}.tmp" && mv "${CFG}.tmp" "$CFG"
printf '%s' "$newhash" > "$HASHFILE"
log "Applied config token to serverconfig.json."
