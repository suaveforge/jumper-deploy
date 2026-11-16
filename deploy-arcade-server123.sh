#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper-games
APP="$ROOT/app"
DATA="$ROOT/data"
NAME=sf-jumper-arcade
IMAGE=node:22.11.0-alpine

# Filesystem creation and persistence happen in the actual server123
# Docker daemon host. Never touch legacy Reldens or HYTOPIA data.
"$D" -H "$S" run --rm -i --network none -v /home:/host-home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
for name in ('app','data','backup'):
    Path('/host-home/jumper-games',name).mkdir(parents=True,exist_ok=True)
print('JUMPER_ARCADE_DIRECTORIES=READY')
PY
test -s "$PWD/games/server.js"
test -s "$PWD/games/client.js"
test -s "$PWD/games/client.css"

# Verify repository JavaScript syntax before writing to host.
"$D" -H "$S" run --rm --network none -v "$PWD/games:/src:ro" "$IMAGE" sh -ec '
  node --check /src/server.js
  node --check /src/client.js
  echo JUMPER_ARCADE_SOURCE_SYNTAX=PASS
'
# Keep previous runnable files for rollback.
"$D" -H "$S" run --rm --network none \
  -v "$APP:/app:rw" -v "$ROOT/backup:/backup:rw" \
  -v "$PWD/games:/src:ro" alpine:3.20 sh -ec '
    if test -f /app/server.js; then
      tar -czf /backup/arcade-app-before-current.tar.gz -C /app \
        server.js client.js client.css package.json node_modules 2>/dev/null || true
    fi
    cp /src/server.js /src/client.js /src/client.css /src/package.json /app/
    echo JUMPER_ARCADE_SOURCE=DEPLOYED
  '

"$D" -H "$S" run --rm --network bridge --memory 600m --pids-limit 192 \
  -v "$APP:/app:rw" -w /app "$IMAGE" \
  npm install --omit=dev --no-audit --no-fund --ignore-scripts
"$D" -H "$S" run --rm --network none -v "$APP:/app:ro" "$IMAGE" \
  sh -ec 'node --check /app/server.js && node --check /app/client.js && test -s /app/node_modules/ws/package.json'

if "$D" -H "$S" inspect "$NAME" >/dev/null 2>&1; then
  "$D" -H "$S" rm -f "$NAME" >/dev/null
fi

"$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
  --network bridge --memory 320m --pids-limit 160 --security-opt no-new-privileges \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  -p 127.0.0.1:18774:8787 \
  -v "$APP:/app:ro" -v "$DATA:/data:rw" \
  -w /app -e PORT=8787 -e DATA_DIR=/data \
  "$IMAGE" node --experimental-sqlite server.js >/dev/null

for i in $(seq 1 28); do
  code=$(curl -sS --max-time 4 -o /tmp/jumper-arcade-health -w '%{http_code}' http://127.0.0.1:18774/health || true)
  if [ "$code" = 200 ] && grep -q '"games":12' /tmp/jumper-arcade-health; then
    echo JUMPER_ARCADE_BACKEND=READY
    echo JUMPER_ARCADE_GAMES=12
    exit 0
  fi
  sleep 2
done
echo JUMPER_ARCADE_BACKEND=FAILED
"$D" -H "$S" logs --tail 65 "$NAME" >&2 || true
exit 1
