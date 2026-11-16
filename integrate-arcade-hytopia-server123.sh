#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network none \
 -v /home/jumper-eval/hytopia:/eval:rw \
 -v /home/jumper-games/backup:/backup:rw \
 python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,time,os
page=Path('/eval/source/client/dist/index.html')
if not page.is_file():raise RuntimeError('JUMPER_HYTOPIA_CLIENT_NOT_BUILT')
html=page.read_text()
if 'jumper-default-server' not in html:raise RuntimeError('JUMPER_HYTOPIA_DEFAULT_JOIN_MISSING')
if '</head>' not in html or '</body>' not in html:raise RuntimeError('JUMPER_HYTOPIA_HTML_UNEXPECTED')
backup=Path('/backup/index.before-arcade.html')
if not backup.exists():
    backup.write_text(html)
    os.chmod(backup,0o600)
version=str(int(time.time()*1000))
style='<link id="jumper-arcade-style" rel="stylesheet" href="/mini/client.css?v='+version+'">'
script='<script id="jumper-arcade-script" defer src="/mini/client.js?v='+version+'"></script>'
if 'id="jumper-arcade-style"' in html:
    html=re.sub(r'<link id="jumper-arcade-style"[^>]*>',style,html,count=1)
else:html=html.replace('</head>',style+'\n</head>',1)
if 'id="jumper-arcade-script"' in html:
    html=re.sub(r'<script id="jumper-arcade-script"[^>]*></script>',script,html,count=1)
else:html=html.replace('</body>',script+'\n</body>',1)
html=html.replace('<title>HYTOPIA</title>','<title>JUMPER | 함께하는 게임 월드</title>',1)
tmp=page.with_name('.index.html.jma-temp')
tmp.write_text(html)
os.replace(tmp,page)
print('JUMPER_ARCADE_FRONTEND_INJECTED=YES')
print('JUMPER_ARCADE_ASSET_VERSION='+version)
PY
