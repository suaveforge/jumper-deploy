#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
IMAGE=node:22-bookworm
NAME=sf-jumper-world-candidate
# All 123 organization runners share one candidate container and bundle path.
# Serialize preparation to stop one job deleting another job's candidate.
command -v flock >/dev/null 2>&1 || { echo JUMPER_CANDIDATE_BUILD_FLOCK_MISSING; exit 1; }
exec 9>/tmp/suaveforge-jumper-candidate-build.lock
flock -w 600 9 || { echo JUMPER_CANDIDATE_BUILD_BUSY; exit 1; }
trap 'flock -u 9' EXIT

test -s "$PWD/world/playground.ts"
test -s "$PWD/world/client.js"
test -s "$PWD/world/client.css"

# Host only the new world candidate; the public server is left running intact.
"$D" -H "$S" run --rm --network none \
  -v "$SRC:/src:rw" -v "$PWD/world:/game:ro" alpine:3.20 sh -ec '
    test -s /src/server/src/playground.mjs
    cp /game/playground.ts /src/server/src/jumper-world.ts
    echo JUMPER_WORLD_SERVER_SOURCE=COPIED
  '

"$D" -H "$S" run --rm --network bridge --memory 3g --pids-limit 1024 \
  -e NODE_OPTIONS=--max-old-space-size=2048 \
  -v "$SRC:/src:rw" -w /src/server "$IMAGE" sh -ec '
    if ! command -v bun >/dev/null 2>&1; then npm install -g --no-audit --no-fund bun@1.3.4; fi
    bun build src/jumper-world.ts --minify --legal-comments=inline \
      --target=node --format=esm --sourcemap=none \
      --outfile=./src/jumper-world.mjs --env=disable \
      --external=@fails-components/webtransport \
      --external=@fails-components/webtransport-transport-http3-quiche
    test -s src/jumper-world.mjs
    node --check src/jumper-world.mjs
    echo JUMPER_WORLD_SERVER_BUNDLE=COMPILED
  '

for i in $(seq 1 15); do
  if ! "$D" -H "$S" inspect "$NAME" >/dev/null 2>&1; then break; fi
  "$D" -H "$S" rm -f "$NAME" >/dev/null 2>&1 || true
  sleep 1
done
test ! "$("$D" -H "$S" ps -a --filter "name=^/$NAME$" --format '{{.Names}}' | grep -x "$NAME" || true)"
"$D" -H "$S" run -d --name "$NAME" --restart no \
 --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
 -p 127.0.0.1:18776:8080/tcp \
 -v "$SRC:/src:rw" -w /src/server -e PORT=8080 -e NODE_ENV=development \
 "$IMAGE" node src/jumper-world.mjs >/dev/null

for i in $(seq 1 50); do
  status=$(curl -ksS --max-time 5 -o /tmp/jumper-world-candidate -w '%{http_code}' https://127.0.0.1:18776/ || true)
  if [ "$status" = 200 ]; then
    echo JUMPER_NATIVE_3D_WORLD_CANDIDATE=READY
    "$D" -H "$S" logs --tail 30 "$NAME" 2>&1 | sed -E 's/(secret|token|password)=([^ ]+)/\1=[REDACTED]/Ig'
    exit 0
  fi
  sleep 3
done
echo JUMPER_NATIVE_3D_WORLD_CANDIDATE=FAILED
"$D" -H "$S" logs --tail 65 "$NAME" >&2 || true
exit 1
