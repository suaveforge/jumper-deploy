#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
SRC=/home/jumper-eval/hytopia/source
BACK=/home/jumper-games/backup

test -s "$PWD/world/client.js"
test -s "$PWD/world/client.css"
"$D" -H "$S" run --rm --network none -v "$PWD/world:/game:ro" node:22.11.0-alpine node --check /game/client.js

"$D" -H "$S" run --rm -i --network none \
  -v "$SRC:/src:rw" -v "$BACK:/backup:rw" \
  -v "$PWD/world:/game:ro" python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,os,time,shutil
dist=Path('/src/client/dist')
page=dist/'index.html'
assert page.is_file(), 'JUMPER_FRONTEND_INDEX_MISSING'
assert (dist/'assets').is_dir(), 'JUMPER_ORIGINAL_3D_ASSETS_MISSING'
backup=Path('/backup/index.before-world-native.html')
html=page.read_text()
assert 'jumper-default-server' in html, 'JUMPER_DEFAULT_BACKEND_BOOTSTRAP_MISSING'
assert 'history.replaceState' in html, 'JUMPER_WEBKIT_RELOAD_FIX_MISSING'
if not backup.exists():
  backup.write_text(html);os.chmod(backup,0o600)
shutil.copyfile('/game/client.js',dist/'world.js')
shutil.copyfile('/game/client.css',dist/'world.css')
version=str(int(time.time()*1000))
# Remove the old standalone 2D arcade launcher, not the server or stored scores.
html=re.sub(r'<link id="jumper-arcade-style"[^>]*>\s*','',html)
html=re.sub(r'<script id="jumper-arcade-script"[^>]*></script>\s*','',html)
html=re.sub(r'<link id="jumper-world-style"[^>]*>\s*','',html)
html=re.sub(r'<script id="jumper-world-script"[^>]*></script>\s*','',html)
style='<link id="jumper-world-style" rel="stylesheet" href="/world.css?v='+version+'">'
script='<script id="jumper-world-script" src="/world.js?v='+version+'"></script>'
assert '</head>' in html and '<script type="module"' in html, 'JUMPER_ORIGINAL_3D_MODULE_MISSING'
html=html.replace('</head>',style+'\n</head>',1)
# Classic script runs before the module, registering SceneUI signs before world sync.
html=html.replace('<script type="module"',script+'\n<script type="module"',1)
html=html.replace('<title>HYTOPIA</title>','<title>JUMPER | 게임이 펼쳐지는 월드</title>')
target=page.with_name('.index.world-staging')
target.write_text(html);os.replace(target,page)
assert not 'jumper-arcade-script' in page.read_text()
print('JUMPER_NATIVE_WORLD_3D_CLIENT=INTEGRATED')
PY
