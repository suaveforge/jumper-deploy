#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
for file in hubs-client.js hubs-client.css authhub-client.js; do
 test -s "$PWD/world/$file"
done
"$D" -H "$S" run --rm --network none -v "$PWD/world:/world:ro" \
 node:22.11.0-alpine sh -ec 'node --check /world/hubs-client.js; node --check /world/hub-gateway.cjs'
"$D" -H "$S" run --rm -i --network none \
 -v "$SRC:/src:rw" -v /home/jumper-hubs/backup:/backup:rw \
 -v "$PWD/world:/world:ro" python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,shutil,os,time
dist=Path('/src/client/dist')
idx=dist/'index.html'
if not idx.is_file():raise RuntimeError('JUMPER_WORLD_INDEX_MISSING')
html=idx.read_text()
if 'jumper-world-script' not in html or 'jumper-arcade-script' in html:
 raise RuntimeError('JUMPER_NATIVE_WORLD_BOOTSTRAP_UNEXPECTED')
back=Path('/backup/index.before-authhub-payhub.html')
if not back.exists():
 back.write_text(html);os.chmod(back,0o600)
for name in ('authhub-client.js','hubs-client.js','hubs-client.css'):
 shutil.copyfile(Path('/world')/name,dist/name)
version=str(int(time.time()*1000))
css='<link id="jumper-hubs-style" rel="stylesheet" href="/hubs-client.css?v='+version+'">'
js='<script id="jumper-hubs-script" defer src="/hubs-client.js?v='+version+'"></script>'
html=re.sub(r'<link id="jumper-hubs-style"[^>]*>\s*','',html)
html=re.sub(r'<script id="jumper-hubs-script"[^>]*></script>\s*','',html)
html=html.replace('</head>',css+'\n</head>',1).replace('</body>',js+'\n</body>',1)
tmp=idx.with_name('.index.jumper-hub-stage');tmp.write_text(html);os.replace(tmp,idx)
print('JUMPER_PUBLIC_AUTHHUB_PAYHUB_CLIENT=INSTALLED')
print('JUMPER_AUTHHUB_CLIENT_TRANSPORT=OFFICIAL_SOURCE')
PY
