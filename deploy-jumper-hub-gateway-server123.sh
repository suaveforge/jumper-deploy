#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper-hubs
APP="$ROOT/app"
DATA="$ROOT/data"
NAME=sf-jumper-hub-gateway
IMAGE=node:22.11.0-alpine
test -s "$PWD/world/hub-gateway.cjs"
"$D" -H "$S" run --rm --network none -v "$PWD/world:/source:ro" "$IMAGE" node --check /source/hub-gateway.cjs
"$D" -H "$S" run --rm -i --network none -v /home:/home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
root=Path('/home/jumper-hubs')
for dir in ('app','data','backup'):
 (root/dir).mkdir(parents=True,exist_ok=True)
products=root/'data/products.json'
if not products.exists():
 products.write_text('[]\n')
 print('JUMPER_PAYHUB_PRODUCT_CATALOG=EMPTY_SAFE_DEFAULT')
# No checkout API key/webhook key is generated or guessed by JUMPER.
PY
"$D" -H "$S" run --rm --network none -v "$APP:/app:rw" -v "$PWD/world:/source:ro" \
 alpine:3.20 cp /source/hub-gateway.cjs /app/hub-gateway.cjs
if "$D" -H "$S" inspect "$NAME" >/dev/null 2>&1; then "$D" -H "$S" rm -f "$NAME" >/dev/null; fi
if test -s "$ROOT/private.env"; then
 "$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
  --network bridge --memory 240m --pids-limit 90 --security-opt no-new-privileges \
  --read-only --tmpfs /tmp:rw,nosuid,noexec,size=16m \
  --env-file "$ROOT/private.env" -p 127.0.0.1:18777:8788 \
  -v "$APP:/app:ro" -v "$DATA:/data:rw" -w /app \
  -e PORT=8788 -e DATA_DIR=/data "$IMAGE" \
  node --experimental-sqlite hub-gateway.cjs >/dev/null
else
 "$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
  --network bridge --memory 240m --pids-limit 90 --security-opt no-new-privileges \
  --read-only --tmpfs /tmp:rw,nosuid,noexec,size=16m \
  -p 127.0.0.1:18777:8788 \
  -v "$APP:/app:ro" -v "$DATA:/data:rw" -w /app \
  -e PORT=8788 -e DATA_DIR=/data "$IMAGE" \
  node --experimental-sqlite hub-gateway.cjs >/dev/null
fi
for i in $(seq 1 30); do
 code=$(curl -sS --max-time 5 -o /tmp/jumper-hubs-health -w '%{http_code}' http://127.0.0.1:18777/health || true)
 if [ "$code" = 200 ]; then
  grep -q '"project":"p51"' /tmp/jumper-hubs-health
  echo JUMPER_AUTHHUB_PAYHUB_GATEWAY=READY
  exit 0
 fi
 sleep 2
done
"$D" -H "$S" logs --tail 25 "$NAME" >&2 || true
exit 1
