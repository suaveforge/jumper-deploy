#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
ACTIVE=sf-jumper-eval-hytopia-server
BACKUP=sf-jumper-pre-auth-identity
if "$D" -H "$S" inspect "$BACKUP" >/dev/null 2>&1; then
 "$D" -H "$S" rm -f "$ACTIVE" >/dev/null 2>&1 || true
 "$D" -H "$S" rename "$BACKUP" "$ACTIVE"
 "$D" -H "$S" update --restart unless-stopped "$ACTIVE" >/dev/null
 "$D" -H "$S" start "$ACTIVE" >/dev/null
fi
"$D" -H "$S" run --rm --network none \
 -v "$SRC:/src:rw" -v /home/jumper-hubs/backup:/backup:ro alpine:3.20 sh -ec '
   if test -s /backup/hubs-client.before-world-identity.js; then
     cp /backup/hubs-client.before-world-identity.js /src/client/dist/hubs-client.js
     echo JUMPER_AUTH_IDENTITY_CLIENT=RESTORED
   fi
 '
for i in $(seq 1 20); do
 code=$(curl -ksS --max-time 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:18773/ || true)
 if [ "$code" = 200 ]; then echo JUMPER_AUTH_IDENTITY_SERVER=ROLLED_BACK;exit 0;fi
 sleep 2
done
exit 1
