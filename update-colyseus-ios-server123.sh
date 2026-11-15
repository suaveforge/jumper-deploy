#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
# Keep the original Reldens package and every game/database file unchanged.
# Only override the Colyseus browser SDK version to the upstream Safari-fixed patch.
"$D" -H "$S" run --rm -i --network none \
  -v /home/jumper/app:/app:rw \
  -v /home/jumper/backups:/backups:rw \
  node:22-bookworm-slim node - <<'JS'
const fs=require('fs'),path=require('path');
const root='/app',b='/backups';
for(const name of ['package.json','package-lock.json']){
 const f=path.join(root,name),dest=path.join(b,name+'.before-colyseus-ios-fix');
 if(fs.existsSync(f)&&!fs.existsSync(dest))fs.copyFileSync(f,dest);
}
const pkg=JSON.parse(fs.readFileSync(path.join(root,'package.json'),'utf8'));
pkg.overrides={...(pkg.overrides||{}),'@colyseus/sdk':'0.18.8'};
fs.writeFileSync(path.join(root,'package.json'),JSON.stringify(pkg,null,2)+'\n');
console.log('JUMPER_COLYSEUS_OVERRIDE=0.18.8');
JS
"$D" -H "$S" run --rm --network sf-jumper-net --memory 3g --pids-limit 1024 \
  -v /home/jumper/app:/app:rw -w /app \
  -e NODE_OPTIONS=--max-old-space-size=2048 \
  node:22-bookworm-slim npm install --no-audit --no-fund --ignore-scripts
"$D" -H "$S" run --rm -i --network none \
  -v /home/jumper/app:/app:ro node:22-bookworm-slim node - <<'JS'
const fs=require('fs'),path=require('path'),module=require('module');
const sdkRequire=module.createRequire('/app/node_modules/reldens/lib/sync/client/colyseus/sync-client-driver.js');
let dir=path.dirname(sdkRequire.resolve('@colyseus/sdk'));
for(let i=0;i<7;i++){
 const f=path.join(dir,'package.json');
 if(fs.existsSync(f)){
  const pkg=JSON.parse(fs.readFileSync(f,'utf8'));
  if(pkg.name==='@colyseus/sdk'){
    console.log('JUMPER_COLYSEUS_ACTUAL_VERSION='+pkg.version);
    if(pkg.version!=='0.18.8')throw Error('SAFARI_SDK_VERSION_MISMATCH');
    process.exit(0);
  }
 }
 dir=path.dirname(dir);
}
throw Error('SAFARI_SDK_NOT_FOUND_FROM_RELDENS');
JS
