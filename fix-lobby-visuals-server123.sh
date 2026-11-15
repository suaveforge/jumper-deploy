#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network none \
  -v /home/jumper/app:/app:rw -v /home/jumper/backups:/backups:rw \
  python:3.11-alpine python - <<'PY'
from pathlib import Path
import os
page=Path('/app/theme/default/index.html')
assert page.is_file(), 'JUMPER_THEME_MISSING'
src=page.read_text()
assert 'id="jumper-lobby-style"' in src and 'form name="login-form"' in src, 'JUMPER_UNEXPECTED_THEME_STOP'
backup=Path('/backups/jumper-lobby-before-visual-correction.html')
if not backup.exists():
    backup.write_text(src)
marker='id="jumper-postfix-css"'
if marker in src:
    print('JUMPER_VISUAL_PATCH=ALREADY_APPLIED')
    raise SystemExit(0)
css="""
/* Only apply to the unauthenticated lobby, never the actual game UI. */
body:not(.game-engine-started) .content .forms-container > .col-2 {min-width:0;}
body:not(.game-engine-started) .content .forms-container > .col-2 > .row.wooden-box:has(> form.hidden) {
  display:none !important;
}
body:not(.game-engine-started) .content .forms-container > .col-2 > .row.wooden-box:has(> .firebase-login.hidden) {
  display:none !important;
}
body:not(.game-engine-started) .content form input[type="submit"] {
  -webkit-appearance:none !important;
  appearance:none !important;
  display:block !important;
  width:100% !important;
  min-height:48px;
  background-color:#2465ba !important;
  color:#fff !important;
  font-size:16px !important;
  font-weight:750 !important;
  line-height:1.3 !important;
  opacity:1 !important;
  border:0 !important;
  border-radius:9px !important;
  text-indent:0 !important;
  -webkit-text-fill-color:#fff !important;
}
body:not(.game-engine-started) .content .guest-form input[type="submit"] {
  background-color:#1a705d !important;
}
body:not(.game-engine-started) .content form input[type="submit"]:hover {
  filter:brightness(.93);
}
body:not(.game-engine-started) .content .row-disclaimer, 
body:not(.game-engine-started) .content .row:has(> form.hidden) {
  display:none !important;
}
body:not(.game-engine-started) .content .forms-container {overflow:visible;}
body:not(.game-engine-started) .wrapper {overflow-x:hidden;}
@media(max-width:730px) {
  body:not(.game-engine-started) .content .forms-container {display:flex;flex-direction:column;}
  body:not(.game-engine-started) .content .forms-container > .col-2 {width:100%;}
}
"""
src=src.replace('</head>', '<style '+marker+'>\n'+css+'\n</style>\n</head>',1)
src=src.replace('href="https://www.dwdeveloper.com/" alt="DwDeveloper" target="_blank">by DwDeveloper',
                'href="https://github.com/damian-pastorini/reldens" rel="noopener noreferrer" target="_blank">Powered by Reldens')
tmp=page.with_name('index.html.jumper-visual-tmp')
tmp.write_text(src)
os.replace(tmp,page)
print('JUMPER_VISUAL_PATCH=APPLIED')
PY
