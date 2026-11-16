#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
NAME=sf-jumper-eval-hytopia-server
BACKUP=sf-jumper-hytopia-before-native-world
CANDIDATE=sf-jumper-world-candidate
IMAGE=node:22-bookworm

test -s "$PWD/world/playground.ts"
test -s "$PWD/world/client.js"
test -s "$PWD/world/client.css"
test "$(curl -ksS --max-time 8 -o /dev/null -w '%{http_code}' https://127.0.0.1:18776/)" = 200
test "$("$D" -H "$S" inspect --format '{{.State.Running}}' "$NAME")" = true
test "$("$D" -H "$S" inspect --format '{{.State.Running}}' "$CANDIDATE")" = true
if "$D" -H "$S" inspect "$BACKUP" >/dev/null 2>&1; then
  echo JUMPER_NATIVE_WORLD_ROLLBACK_SLOT_CONFLICT
  exit 1
fi
"$D" -H "$S" run --rm --network none -v "$SRC:/src:ro" alpine:3.20 sh -ec '
 test -s /src/server/src/jumper-world.mjs
 test -s /src/server/src/playground.mjs
'

restore(){
  echo JUMPER_NATIVE_WORLD_RELEASE_FAILED_RESTORING
  "$D" -H "$S" rm -f "$NAME" >/dev/null 2>&1 || true
  if "$D" -H "$S" inspect "$BACKUP" >/dev/null 2>&1; then
    "$D" -H "$S" rename "$BACKUP" "$NAME" >/dev/null || true
    "$D" -H "$S" update --restart unless-stopped "$NAME" >/dev/null || true
    "$D" -H "$S" start "$NAME" >/dev/null || true
  fi
}
trap 'restore' EXIT
# Keep old image, container and original compiled source for instant rollback.
"$D" -H "$S" update --restart no "$NAME" >/dev/null
"$D" -H "$S" stop -t 20 "$NAME" >/dev/null
"$D" -H "$S" rename "$NAME" "$BACKUP" >/dev/null
"$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
  --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
  -p 127.0.0.1:18773:8080/tcp \
  -v "$SRC:/src:rw" -w /src/server -e PORT=8080 -e NODE_ENV=development \
  "$IMAGE" node src/jumper-world.mjs >/dev/null
ready=0
for i in $(seq 1 40); do
  code=$(curl -ksS --max-time 5 -o /tmp/jumper-world-promote -w '%{http_code}' https://127.0.0.1:18773/ || true)
  if [ "$code" = 200 ]; then ready=1;break;fi
  sleep 2
done
test "$ready" = 1
echo JUMPER_NATIVE_WORLD_PUBLIC_SERVER=HTTP_200
# Keep rollback object stopped; cleanup candidate only after production validation.
trap - EXIT
echo JUMPER_NATIVE_WORLD_SERVER_PROMOTED=YES
