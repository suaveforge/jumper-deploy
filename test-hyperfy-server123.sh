#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper-eval/hyperfy
SRC="$ROOT/source"
NAME=sf-jumper-eval-hyperfy
IMAGE=node:22.11.0-alpine

# All source, assets, and persisted data live outside the retired Reldens directory.
"$D" -H "$S" run --rm -i --network none -v /home:/host-home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import secrets,os
root=Path('/host-home/jumper-eval/hyperfy')
src=root/'source'
for p in (root,src,root/'logs'):
    p.mkdir(parents=True,exist_ok=True)
PY
if ! "$D" -H "$S" run --rm --network none -v "$SRC:/src:ro" alpine:3.20 test -s /src/package.json; then
  "$D" -H "$S" run --rm --network bridge --memory 400m --pids-limit 128 \
    -v "$SRC:/src:rw" --entrypoint /bin/sh alpine/git -ec \
    'git clone --depth 1 https://github.com/hyperfy-xyz/hyperfy.git /src'
fi

# Never leave the documented insecure empty admin code enabled.
"$D" -H "$S" run --rm -i --network none \
  -v "$SRC:/app:rw" python:3.11-alpine python - <<'PY'
from pathlib import Path
import secrets,os
root=Path('/app')
env=root/'.env'
if not env.exists():
    env.write_text(
      'WORLD=world\n'
      'PORT=3000\n'
      'JWT_SECRET='+secrets.token_hex(32)+'\n'
      'ADMIN_CODE='+secrets.token_urlsafe(24)+'\n'
      'SAVE_INTERVAL=60\n'
      'PUBLIC_PLAYER_COLLISION=false\n'
      'PUBLIC_MAX_UPLOAD_SIZE=8\n'
      'PUBLIC_WS_URL=wss://jumper-hyperfy.suaveforge.com/ws\n'
      'PUBLIC_API_URL=https://jumper-hyperfy.suaveforge.com/api\n'
      'ASSETS=local\n'
      'ASSETS_BASE_URL=https://jumper-hyperfy.suaveforge.com/assets\n'
      'DB_URI=local\n'
      'CLEAN=false\n'
    )
    os.chmod(env,0o600)
if not (root/'package.json').is_file():
    raise RuntimeError('HYPERFY_SOURCE_MISSING')
print('HYPERFY_SOURCE=READY')
print('HYPERFY_SAFE_ADMIN_CODE=SET_NOT_PRINTED')
PY

"$D" -H "$S" run --rm --network bridge --memory 4g --pids-limit 1536 \
  -v "$SRC:/app:rw" -w /app -e NODE_OPTIONS=--max-old-space-size=3072 \
  "$IMAGE" sh -ec 'npm ci --no-audit --no-fund && npm run build'

# Launch with persistent world sqlite, only on a loopback high port.
if "$D" -H "$S" inspect "$NAME" >/dev/null 2>&1; then
  "$D" -H "$S" rm -f "$NAME" >/dev/null
fi
"$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
  --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
  -p 127.0.0.1:18771:3000 \
  -v "$SRC:/app:rw" -w /app --env-file "$SRC/.env" \
  -e NODE_ENV=production \
  "$IMAGE" node build/index.js >/dev/null
for n in $(seq 1 35); do
  status=$(curl -sS --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:18771/status || true)
  if [ "$status" = 200 ]; then
    echo "HYPERFY_STATUS=200"
    break
  fi
  sleep 3
done
test "$status" = 200 || { echo 'HYPERFY_STARTUP=FAILED'; "$D" -H "$S" logs --tail 35 "$NAME" 2>&1 | sed -E 's/(secret|token|password)=([^ ]+)/\1=[REDACTED]/Ig'; exit 1; }
html=$(curl -sS --max-time 10 http://127.0.0.1:18771/)
printf '%s' "$html" | grep -Eiq 'html|hyperfy' || { echo HYPERFY_FRONTEND=FAILED; exit 1; }
echo HYPERFY_FRONTEND=READY_LOOPBACK
echo HYPERFY_PORT=18771
