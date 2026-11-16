#!/bin/sh
set -eu
# Every GitHub run owns its own immutable entry bundle, container and host port.
# Do not write into /home/jumper-eval/hytopia/source before the release stage.
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
RUN=$GITHUB_RUN_ID
test -n "$RUN"
PORT=$((22000 + RUN % 9000))
NAME=sf-jumper-nav-$RUN
DIR=/home/jumper-nav-candidates/$RUN
test -s "$PWD/world/playground.ts"
test -s "$PWD/world/client.js"
test -s "$PWD/world/client.css"
if "$D" -H "$S" inspect "$NAME" >/dev/null 2>&1; then
  echo JUMPER_ISOLATED_CANDIDATE_ALREADY_EXISTS
  exit 1
fi
"$D" -H "$S" run --rm --network none \
  -v /home/jumper-nav-candidates:/data:rw alpine:3.20 \
  sh -ec 'mkdir -p "/data/'"$RUN"'/backup" "/data/'"$RUN"'/data"; : > "/data/'"$RUN"'/jumper-world.mjs"; : > "/data/'"$RUN"'/jumper-world-scores.json"'
"$D" -H "$S" run --rm --network bridge --memory 3g --pids-limit 1024 \
  -e NODE_OPTIONS=--max-old-space-size=2048 \
  -v "$SRC:/src:ro" \
  -v "$PWD/world/playground.ts:/src/server/src/jumper-world.ts:ro" \
  -v "$DIR/jumper-world.mjs:/src/server/src/jumper-world.mjs:rw" \
  -w /src/server node:22-bookworm sh -ec '
    if ! command -v bun >/dev/null 2>&1; then npm install -g --no-audit --no-fund bun@1.3.4; fi
    bun build src/jumper-world.ts --minify --legal-comments=inline \
      --target=node --format=esm --sourcemap=none \
      --outfile=./src/jumper-world.mjs --env=disable \
      --external=@fails-components/webtransport \
      --external=@fails-components/webtransport-transport-http3-quiche
    test -s src/jumper-world.mjs
    node --check src/jumper-world.mjs
  '
"$D" -H "$S" run -d --name "$NAME" --restart no \
  --network bridge --memory 2g --pids-limit 512 --security-opt no-new-privileges \
  -p "127.0.0.1:$PORT:8080/tcp" \
  -v "$SRC:/src:ro" \
  -v "$DIR/jumper-world.mjs:/src/server/src/jumper-world.mjs:ro" \
  -v "$DIR/jumper-world-scores.json:/src/server/jumper-world-scores.json:rw" \
  -v "$DIR/data:/var/lib/jumper-tournament:rw" \
  -w /src/server -e PORT=8080 -e NODE_ENV=development \
  -e JUMPER_NAV_DROP_FIRST_ACK=1 \
  -e JUMPER_TOURNAMENT_DATA_DIR=/var/lib/jumper-tournament \
  node:22-bookworm node src/jumper-world.mjs >/dev/null
ready=0
for i in $(seq 1 50); do
  status=$(curl -ksS --max-time 4 -o /dev/null -w '%{http_code}' "https://127.0.0.1:$PORT/" || true)
  if [ "$status" = 200 ]; then ready=1;break;fi
  sleep 2
done
if [ "$ready" -ne 1 ]; then
  "$D" -H "$S" logs --tail 80 "$NAME" >&2 || true
  exit 1
fi
printf 'JUMPER_NAV_PORT=%s\nJUMPER_NAV_CONTAINER=%s\nJUMPER_NAV_DIR=%s\n' \
  "$PORT" "$NAME" "$DIR" > "$PWD/.jumper-nav-candidate.env"
echo JUMPER_NAV_CANDIDATE_ISOLATED=PASS
echo "JUMPER_NAV_CANDIDATE_PORT=$PORT"
echo "JUMPER_NAV_CANDIDATE_NAME=$NAME"
