#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
CURRENT=sf-jumper-eval-hytopia-server
PREVIOUS=sf-jumper-hytopia-before-native-world
SRC=/home/jumper-eval/hytopia/source
BACK=/home/jumper-games/backup/index.before-world-native.html
if ! "$D" -H "$S" inspect "$PREVIOUS" >/dev/null 2>&1; then
 echo JUMPER_WORLD_ROLLBACK_NO_SAVED_CONTAINER
 exit 1
fi
"$D" -H "$S" rm -f "$CURRENT" >/dev/null 2>&1 || true
"$D" -H "$S" rename "$PREVIOUS" "$CURRENT"
"$D" -H "$S" update --restart unless-stopped "$CURRENT" >/dev/null
"$D" -H "$S" start "$CURRENT" >/dev/null
"$D" -H "$S" run --rm -i --network none -v "$SRC:/src:rw" \
  -v /home/jumper-games/backup:/backup:ro python:3.11-alpine python - <<'PY'
from pathlib import Path
import os
backup=Path('/backup/index.before-world-native.html')
page=Path('/src/client/dist/index.html')
assert backup.is_file(), 'JUMPER_OLD_UI_BACKUP_MISSING'
tmp=page.with_name('.index.jumper-rollback')
tmp.write_bytes(backup.read_bytes())
os.replace(tmp,page)
print('JUMPER_NATIVE_WORLD_FRONTEND_ROLLED_BACK=YES')
PY
for i in $(seq 1 30); do
 code=$(curl -ksS --max-time 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:18773/ || true)
 if [ "$code" = 200 ]; then echo JUMPER_OLD_MMO_BACKEND_ROLLBACK=HEALTHY;exit 0;fi
 sleep 2
done
echo JUMPER_OLD_MMO_BACKEND_ROLLBACK=FAILED
exit 1
