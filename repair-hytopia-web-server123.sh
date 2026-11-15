#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
SERVER=sf-jumper-eval-hytopia-server
WEB=sf-jumper-eval-hytopia-web
test "$("$D" -H "$S" inspect --format '{{.State.Running}}' "$SERVER")" = true
"$D" -H "$S" rm -f "$WEB" >/dev/null 2>&1 || true
"$D" -H "$S" run -d --name "$WEB" --restart unless-stopped \
  --network bridge --memory 700m --pids-limit 256 --security-opt no-new-privileges \
  -p 127.0.0.1:18772:5173 \
  -v "$SRC:/src:rw" -w /src/client node:22-bookworm \
  node node_modules/vite/bin/vite.js preview --host 0.0.0.0 --port 5173 --strictPort >/dev/null
for i in $(seq 1 20); do
  code=$(curl -sS --max-time 4 -o /tmp/jumper-hytopia-repaired -w '%{http_code}' http://127.0.0.1:18772/ || true)
  if [ "$code" = 200 ]; then
    echo HYTOPIA_REPAIRED_FRONTEND_HTTP=200
    exit 0
  fi
  sleep 2
done
echo HYTOPIA_REPAIRED_FRONTEND=FAILED
"$D" -H "$S" logs --tail 24 "$WEB" >&2
exit 1
