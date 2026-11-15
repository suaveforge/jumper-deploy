#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper-eval/hytopia
SRC="$ROOT/source"
IMAGE=node:22-bookworm
SERVER=sf-jumper-eval-hytopia-server
WEB=sf-jumper-eval-hytopia-web
"$D" -H "$S" run --rm -i --network none -v /home:/host-home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
root=Path('/host-home/jumper-eval/hytopia')
for p in (root,root/'source',root/'logs'):
    p.mkdir(parents=True,exist_ok=True)
PY
if ! "$D" -H "$S" run --rm --network none -v "$SRC:/src:ro" alpine:3.20 test -s /src/server/package.json; then
  "$D" -H "$S" run --rm --network bridge --memory 400m --pids-limit 128 \
    -v "$SRC:/src:rw" --entrypoint /bin/sh alpine/git -ec \
    'git clone --depth 1 https://github.com/hytopiagg/hytopia-source.git /src'
fi
"$D" -H "$S" run --rm --network none -v "$SRC:/src" alpine:3.20 sh -ec '
  test -s /src/server/src/playground.ts
  test -s /src/client/package.json
  test -d /src/assets/release/maps
  if ! test -e /src/server/assets; then ln -s ../assets/release /src/server/assets; fi
  echo HYTOPIA_SOURCE_AND_ASSETS=READY
'

# Compile original server playground and the original browser client. Never modify
# the shared JUMPER deployment, original Reldens data, or system Node installation.
"$D" -H "$S" run --rm --network bridge --memory 3g --pids-limit 1024 \
  -e NODE_OPTIONS=--max-old-space-size=2048 \
  -v "$SRC:/src:rw" -w /src/server "$IMAGE" sh -ec '
    if ! test -s src/playground.mjs; then
      npm ci --no-audit --no-fund
      npm install -g --no-audit --no-fund bun@1.3.4
      npm run build:playground
    fi
    test -s src/playground.mjs
    echo HYTOPIA_SERVER_COMPILED=YES
  '
# Upstream 2026-11-16 client source declares a health-check result which is
# never used. Preserve the call while removing only the unused binding.
"$D" -H "$S" run --rm -i --network none -v "$SRC:/src:rw" python:3.11-alpine python - <<'PY'
from pathlib import Path
p=Path('/src/client/src/network/NetworkManager.ts')
data=p.read_text()
old='const serverHealthy = await Servers.isCurrentServerHealthy().catch(() => false);'
new='await Servers.isCurrentServerHealthy().catch(() => false);'
if old in data:
    p.write_text(data.replace(old,new,1))
    print('HYTOPIA_TS6133_PATCH=APPLIED')
elif new in data:
    print('HYTOPIA_TS6133_PATCH=ALREADY_PRESENT')
else:
    raise RuntimeError('HYTOPIA_UPSTREAM_CODE_CHANGED')
PY
"$D" -H "$S" run --rm --network bridge --memory 3g --pids-limit 1024 \
  -e NODE_OPTIONS=--max-old-space-size=2048 \
  -v "$SRC:/src:rw" -w /src/client "$IMAGE" sh -ec '
    test -d node_modules || npm ci --no-audit --no-fund
    npm run build
    test -s dist/index.html
    echo HYTOPIA_BROWSER_COMPILED=YES
  '

# Original server uses local TLS (trusted only by its local hostname) and a UDP
# WebTransport channel. Keep both engines on loopback, no public access.
for name in "$SERVER" "$WEB"; do
  if "$D" -H "$S" inspect "$name" >/dev/null 2>&1; then "$D" -H "$S" rm -f "$name" >/dev/null; fi
done
"$D" -H "$S" run -d --name "$SERVER" --restart unless-stopped \
  --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
  -p 127.0.0.1:18773:8080/tcp \
  -v "$SRC:/src:rw" -w /src/server -e PORT=8080 -e NODE_ENV=development \
  "$IMAGE" node src/playground.mjs >/dev/null
"$D" -H "$S" run -d --name "$WEB" --restart unless-stopped \
  --network bridge --memory 700m --pids-limit 256 --security-opt no-new-privileges \
  -p 127.0.0.1:18772:5173 \
  -v "$SRC:/src:ro" -w /src/client \
  "$IMAGE" node node_modules/vite/bin/vite.js preview --host 0.0.0.0 --port 5173 --strictPort >/dev/null
server_ok=0
web_ok=0
for i in $(seq 1 35); do
  server_code=$(curl -ksS --max-time 4 -o /tmp/hytopia-server.json -w '%{http_code}' https://127.0.0.1:18773/ || true)
  web_code=$(curl -sS --max-time 4 -o /tmp/hytopia-web.html -w '%{http_code}' http://127.0.0.1:18772/ || true)
  [ "$server_code" = 200 ] && server_ok=1
  [ "$web_code" = 200 ] && web_ok=1
  if [ "$server_ok" = 1 ] && [ "$web_ok" = 1 ]; then break; fi
  sleep 3
done
echo "HYTOPIA_SERVER_HTTP=$server_code"
echo "HYTOPIA_WEB_HTTP=$web_code"
if [ "$server_ok" != 1 ] || [ "$web_ok" != 1 ]; then
  for name in "$SERVER" "$WEB"; do
    echo "LAST_LOGS_$name"
    "$D" -H "$S" logs --tail 20 "$name" 2>&1 | sed -E 's/(secret|token|password)=([^ ]+)/\1=[REDACTED]/Ig' || true
  done
  exit 1
fi
echo HYTOPIA_LOCAL_CLIENT_AND_SERVER=PASS
