#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper
NETWORK=sf-jumper-net
APP=sf-jumper
DB=sf-jumper-db

# Prepare dedicated volumes and secrets inside the daemon's host filesystem.
"$D" -H "$S" run --rm -i --network none -v /home:/host-home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import os,secrets
root=Path('/host-home/jumper')
for name in ('app','db','secrets','deploy','logs'):
    d=root/name
    d.mkdir(parents=True,exist_ok=True)
env=root/'secrets/db.env'
if not env.exists():
    env.write_text('MARIADB_DATABASE=jumper\nMARIADB_USER=jumper\nMARIADB_PASSWORD='+secrets.token_hex(24)+'\nMARIADB_ROOT_PASSWORD='+secrets.token_hex(32)+'\n')
    os.chmod(env,0o600)
secure=root/'secrets/app-secrets.env'
if not secure.exists():
    secure.write_text('JUMPER_ADMIN_SECRET='+secrets.token_hex(32)+'\nJUMPER_SIGN_SECRET='+secrets.token_hex(32)+'\n')
    os.chmod(secure,0o600)
print('JUMPER_HOST_FOLDERS=READY')
PY
"$D" -H "$S" network inspect "$NETWORK" >/dev/null 2>&1 || "$D" -H "$S" network create "$NETWORK" >/dev/null
if ! "$D" -H "$S" container inspect "$DB" >/dev/null 2>&1; then
    "$D" -H "$S" run -d --name "$DB" --restart unless-stopped \
      --network "$NETWORK" --memory 512m --pids-limit 192 \
      -v "$ROOT/secrets/db.env:/run/jumper-db.env:ro" \
      -v "$ROOT/db:/var/lib/mysql" \
      --entrypoint /bin/sh mariadb:11.4 \
      -c 'set -a; . /run/jumper-db.env; exec /usr/local/bin/docker-entrypoint.sh mariadbd' >/dev/null
else
    "$D" -H "$S" start "$DB" >/dev/null || true
fi

# Do not overwrite existing source, database or installer state.
if ! "$D" -H "$S" run --rm --network none -v "$ROOT/app:/app" alpine:3.20 test -s /app/index.js; then
    "$D" -H "$S" run --rm --network "$NETWORK" \
      -v "$ROOT/app:/app" -w /app node:22-bookworm-slim \
      sh -ec 'npm install --no-audit --no-fund reldens@4.0.0-beta.39.9 && npx --no-install reldens createApp'
fi

if "$D" -H "$S" container inspect "$APP" >/dev/null 2>&1; then
    "$D" -H "$S" rm -f "$APP" >/dev/null
fi
"$D" -H "$S" run -d --name "$APP" --restart unless-stopped \
  --network "$NETWORK" --memory 1g --pids-limit 256 \
  -p 127.0.0.1:18766:8080 \
  -v "$ROOT/app:/app:rw" \
  -w /app \
  -e RELDENS_APP_HOST=http://0.0.0.0 \
  -e RELDENS_APP_PORT=8080 \
  -e RELDENS_PUBLIC_URL=https://jumper.suaveforge.com \
  -e RELDENS_DB_HOST="$DB" \
  -e RELDENS_DB_PORT=3306 \
  -e RELDENS_DB_NAME=jumper \
  -e RELDENS_STORAGE_DRIVER=knex \
  -e RELDENS_DB_CLIENT=mysql2 \
  node:22-bookworm-slim node index.js >/dev/null
echo JUMPER_CONTAINERS_STARTED
