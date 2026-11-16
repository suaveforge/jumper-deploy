#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
NAME=sf-jumper-eval-hytopia-server
OLD=sf-jumper-pre-shared-quiz
CANDIDATE=sf-jumper-world-candidate
SRC=/home/jumper-eval/hytopia/source
test "$("$D" -H "$S" inspect -f '{{.State.Running}}' "$CANDIDATE")" = true
test "$(curl -ksS --max-time 10 -o /dev/null -w '%{http_code}' https://127.0.0.1:18776/)" = 200
test "$("$D" -H "$S" inspect -f '{{.State.Running}}' "$NAME")" = true
if "$D" -H "$S" inspect "$OLD" >/dev/null 2>&1; then
 echo JUMPER_SHARED_QUIZ_ROLLBACK_SLOT_EXISTS
 exit 1
fi
restore(){
 "$D" -H "$S" rm -f "$NAME" >/dev/null 2>&1 || true
 if "$D" -H "$S" inspect "$OLD" >/dev/null 2>&1; then
  "$D" -H "$S" rename "$OLD" "$NAME" >/dev/null || true
  "$D" -H "$S" update --restart unless-stopped "$NAME" >/dev/null || true
  "$D" -H "$S" start "$NAME" >/dev/null || true
 fi
}
trap restore EXIT
"$D" -H "$S" update --restart no "$NAME" >/dev/null
"$D" -H "$S" stop -t 18 "$NAME" >/dev/null
"$D" -H "$S" rename "$NAME" "$OLD" >/dev/null
"$D" -H "$S" run -d --name "$NAME" --restart unless-stopped \
 --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
 -p 127.0.0.1:18773:8080/tcp \
 -v "$SRC:/src:rw" -w /src/server -e PORT=8080 -e NODE_ENV=development \
 node:22-bookworm node src/jumper-world.mjs >/dev/null
ok=0
for i in $(seq 1 35); do
 code=$(curl -ksS --max-time 5 -o /dev/null -w '%{http_code}' https://127.0.0.1:18773/ || true)
 if [ "$code" = 200 ]; then ok=1;break;fi
 sleep 2
done
test "$ok" = 1
trap - EXIT
echo JUMPER_SHARED_WORLD_SERVER_PROMOTED=PASS
echo JUMPER_SHARED_WORLD_ROLLBACK_CONTAINER="$OLD"
