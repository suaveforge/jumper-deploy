#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network none \
  -v /home/jumper-eval/hytopia:/eval:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import os
src=Path('/eval/source/client/dist/index.html')
assert src.is_file(), 'JUMPER_HYTOPIA_FRONTEND_NOT_BUILT'
html=src.read_text()
marker='id="jumper-default-server"'
if marker in html:
    print('JUMPER_HYTOPIA_DEFAULT_SERVER=ALREADY_SET')
    raise SystemExit(0)
backup=Path('/eval/index.before-jumper-default-server.html')
if not backup.exists():backup.write_text(html)
script='''<script id="jumper-default-server">
  if (!new URLSearchParams(location.search).has('join')) {
    const url = new URL(location.href);
    url.searchParams.set('join', 'api-jumper.suaveforge.com');
    location.replace(url.toString());
  }
</script>
'''
assert '</head>' in html, 'JUMPER_HYTOPIA_MISSING_HEAD'
html=html.replace('</head>',script+'</head>',1)
tmp=src.with_name('.index.html.jumper-tmp')
tmp.write_text(html)
os.replace(tmp,src)
print('JUMPER_HYTOPIA_DEFAULT_SERVER=CONFIGURED')
PY
