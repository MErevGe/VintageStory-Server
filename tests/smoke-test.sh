#!/usr/bin/env bash
# Smoke and integration tests for a built image. Usage: smoke-test.sh <image>
# Env: EXPECT_DOTNET (major version), TEST_VS_VERSION (VS version to boot).
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image>}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"
EXPECT_DOTNET="${EXPECT_DOTNET:-10}"
TEST_VS_VERSION="${TEST_VS_VERSION:-}"
VS_ARGS=(); [[ -n "$TEST_VS_VERSION" ]] && VS_ARGS=(-e "VS_VERSION=${TEST_VS_VERSION}")

pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*" >&2; exit 1; }
sec()  { echo; echo "== $*"; }

cid=""; cid2=""; mc=""
vol="vs-smoke-$$"
cleanup() {
  for c in "$cid" "$cid2" "$mc"; do [[ -n "$c" ]] && docker rm -f "$c" >/dev/null 2>&1 || true; done
  docker volume rm "$vol" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_exec() { # container, sh-check, timeout
  local c="$1" check="$2" d=$((SECONDS + ${3:-30}))
  while (( SECONDS < d )); do docker exec "$c" sh -c "$check" >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}

sec "1/7 Required tools"
docker run --rm --entrypoint bash "$IMAGE" -lc \
  'command -v curl && command -v jq && command -v gosu && command -v dotnet && command -v unzip' >/dev/null \
  || fail "missing tool"
pass "curl, jq, gosu, dotnet, unzip"

sec "2/7 .NET ${EXPECT_DOTNET} runtime"
docker run --rm --entrypoint dotnet "$IMAGE" --list-runtimes \
  | grep -qE "Microsoft\.NETCore\.App ${EXPECT_DOTNET}\." || fail ".NET ${EXPECT_DOTNET} not found"
pass ".NET ${EXPECT_DOTNET} present"

sec "3/7 Scripts executable"
docker run --rm --entrypoint bash "$IMAGE" -lc \
  'test -x /app/scripts/entrypoint.sh && test -x /app/scripts/install-server.sh && test -x /app/scripts/download-mods.sh' \
  || fail "scripts missing"
pass "scripts present"

sec "4/7 No mods configured is handled"
docker run --rm --entrypoint bash "$IMAGE" -lc \
  'MODS_FILE=/data/.mods.txt MODS_DIR=/tmp/m /app/scripts/download-mods.sh' \
  | grep -qi 'no mods file' || fail "did not skip when no mods are configured"
pass "no mods configured handled"

sec "5/7 VS_MODS env builds the mod list"
mc="$(docker run -d -e VS_MODS="carryon foo@1.2.3" "${VS_ARGS[@]}" "$IMAGE")"
wait_exec "$mc" 'grep -qx carryon /data/.mods.txt && grep -qx "foo@1.2.3" /data/.mods.txt' 30 \
  || { docker exec "$mc" sh -c 'cat /data/.mods.txt' 2>&1 | sed 's/^/    /'; fail "VS_MODS not turned into a mod list"; }
docker rm -f "$mc" >/dev/null 2>&1; mc=""
pass "VS_MODS built the mod list"

sec "6/7 Server boots, mod downloads, serverconfig applies"
cid="$(docker run -d -v "${vol}:/data" \
  -e VS_MODS=carryon -e VS_WHITELIST_MODE=1 -e VS_SERVER_NAME="CI Test Server" \
  "${VS_ARGS[@]}" "$IMAGE")"
deadline=$((SECONDS + BOOT_TIMEOUT)); booted=0
while (( SECONDS < deadline )); do
  logs="$(docker logs "$cid" 2>&1 || true)"
  grep -qiE 'dedicated server now running|all threads started' <<<"$logs" && { booted=1; break; }
  [[ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null)" != "true" ]] \
    && { echo "$logs" | tail -n 30; fail "container exited before booting"; }
  sleep 3
done
(( booted == 1 )) || { docker logs "$cid" 2>&1 | tail -n 30; fail "server did not boot in ${BOOT_TIMEOUT}s"; }
pass "server booted"

docker exec "$cid" sh -c 'ls /data/Mods/*.zip >/dev/null 2>&1' || fail "no mod downloaded"
docker exec "$cid" sh -c 'ls /data/Mods' | grep -qi carryon || fail "carryon not downloaded"
pass "carryon downloaded at runtime"

# carryon 2.x (on VS 1.22) depends on carryonlib, which must be auto-resolved.
if [[ "$EXPECT_DOTNET" == "10" ]]; then
  docker exec "$cid" sh -c 'ls /data/Mods' | grep -qi carryonlib || fail "dependency carryonlib not resolved"
  pass "dependency carryonlib resolved automatically"
fi

cfg="$(docker exec "$cid" sh -c 'cat /data/serverconfig.json' 2>/dev/null || true)"
[[ "$(jq -r '.WhitelistMode' <<<"$cfg" 2>/dev/null)" == "1" ]] || fail "WhitelistMode not applied"
[[ "$(jq -r '.ServerName' <<<"$cfg" 2>/dev/null)" == "CI Test Server" ]] || fail "ServerName not applied"
pass "serverconfig overrides applied"

sec "7/7 Restart reuses cached server (no re-download)"
docker stop "$cid" >/dev/null 2>&1 || true
cid2="$(docker run -d -v "${vol}:/data" "${VS_ARGS[@]}" "$IMAGE")"
deadline=$((SECONDS + 60)); decision=""
while (( SECONDS < deadline )); do
  l="$(docker logs "$cid2" 2>&1 || true)"
  grep -qi 'already installed' <<<"$l" && { decision=skip; break; }
  grep -qiE 'Downloading https' <<<"$l" && { decision=download; break; }
  sleep 2
done
[[ "$decision" == "skip" ]] \
  || { docker logs "$cid2" 2>&1 | grep -i install-server | sed 's/^/    /'; fail "server re-downloaded on restart"; }
pass "cached server reused"

echo; echo "All smoke tests passed."
