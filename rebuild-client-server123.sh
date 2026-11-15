#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper
# Never modify database or regenerate an app skeleton. The database already has live accounts.
# First prove that the server generated a populated client config, not the empty pre-install config.
"$D" -H "$S" run --rm --network none -v "$ROOT/app:/app:ro" node:22-bookworm-slim \
  node -e '
  const fs=require("fs");
  const raw=fs.readFileSync("/app/theme/default/config.js","utf8");
  const prefix="window.reldensInitialConfig = ";
  if(!raw.startsWith(prefix))throw Error("JUMPER_CLIENT_CONFIG_SHAPE_INVALID");
  const obj=JSON.parse(raw.slice(prefix.length).replace(/;\s*$/,""));
  const users=obj.client?.general?.users||{};
  const rooms=obj.client?.rooms?.selection?.availableRooms?.registrationGuest||[];
  console.log("JUMPER_GENERATED_CONFIG_REGISTRATION="+!!users.allowRegistration);
  console.log("JUMPER_GENERATED_CONFIG_GUEST="+!!users.allowGuest);
  console.log("JUMPER_GENERATED_CONFIG_GUEST_ROOMS="+Object.keys(rooms).length);
  if(!users.allowRegistration||!users.allowGuest||!Object.keys(rooms).length)
    throw Error("JUMPER_GENERATED_CONFIG_INCOMPLETE_REFUSE_REBUILD");
  '
# Backup static assets before changing them. DB and existing processes remain untouched.
"$D" -H "$S" run --rm --network none -v "$ROOT/app:/app:ro" -v "$ROOT/backups:/backups:rw" alpine:3.20 \
  sh -ec 'test -s /backups/jumper-dist-before-config-regeneration.tar.gz || tar -czf /backups/jumper-dist-before-config-regeneration.tar.gz -C /app dist'
# Run the upstream client bundler once, isolated from the serving game process.
"$D" -H "$S" run --rm --network none --memory 3g --pids-limit 2048 \
  -v "$ROOT/app:/app:rw" -w /app -e NODE_OPTIONS=--max-old-space-size=2048 \
  node:22-bookworm-slim node node_modules/reldens/bin/reldens-commands.js buildClient
echo JUMPER_CLIENT_BUNDLE_REBUILT=YES
