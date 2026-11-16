#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
ACTIVE=sf-jumper-eval-hytopia-server
BACKUP=sf-jumper-pre-auth-identity
CANDIDATE=sf-jumper-world-candidate
test "$("$D" -H "$S" inspect --format '{{.State.Running}}' "$ACTIVE")" = true
test "$("$D" -H "$S" inspect --format '{{.State.Running}}' "$CANDIDATE")" = true
test "$(curl -ksS --max-time 8 -o /dev/null -w '%{http_code}' https://127.0.0.1:18776/)" = 200
test -s "$PWD/world/playground.ts"
test -s "$PWD/world/hubs-client.js"
if "$D" -H "$S" inspect "$BACKUP" >/dev/null 2>&1; then
 echo JUMPER_HUB_IDENTITY_ROLLBACK_CONFLICT
 exit 1
fi
rollback(){
 echo JUMPER_HUB_IDENTITY_RELEASE_FAILED_ROLLBACK
 "$D" -H "$S" rm -f "$ACTIVE" >/dev/null 2>&1 || true
 if "$D" -H "$S" inspect "$BACKUP" >/dev/null 2>&1; then
   "$D" -H "$S" rename "$BACKUP" "$ACTIVE" >/dev/null || true
   "$D" -H "$S" update --restart unless-stopped "$ACTIVE" >/dev/null || true
   "$D" -H "$S" start "$ACTIVE" >/dev/null || true
 fi
}
trap rollback EXIT
"$D" -H "$S" update --restart no "$ACTIVE" >/dev/null
"$D" -H "$S" stop -t 15 "$ACTIVE" >/dev/null
"$D" -H "$S" rename "$ACTIVE" "$BACKUP" >/dev/null
"$D" -H "$S" run -d --name "$ACTIVE" --restart unless-stopped \
 --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
 -p 127.0.0.1:18773:8080/tcp \
 -v "$SRC:/src:rw" -w /src/server -e PORT=8080 -e NODE_ENV=development \
 node:22-bookworm node src/jumper-world.mjs >/dev/null
ready=0
for i in $(seq 1 35); do
 status=$(curl -ksS --max-time 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:18773/ || true)
 if [ "$status" = 200 ]; then ready=1;break;fi
 sleep 2
done
test "$ready" = 1
trap - EXIT
echo JUMPER_AUTH_IDENTITY_WORLD_PROMOTED=PASS
echo JUMPER_PREVIOUS_WORLD_CONTAINER="$BACKUP"
