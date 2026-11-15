#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network none \
 -v /home/jumper/app/dist:/dist:rw -v /home/jumper/backups:/backups:rw \
 python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,time,os
root=Path('/dist')
assert (root/'index.html').is_file(),'JUMPER_COMPILED_ENTRY_NOT_FOUND'
version=str(int(time.time()*1000))
regex=re.compile(r'(?P<attr>\b(?:src|href))=(?P<quote>["\x27])(?P<url>(?:/|\./)[^"\x27?]+\.(?:js|css))(?:\?[^"\x27]*)?(?P=quote)',re.I)
total=0
for file in sorted(root.glob('*.html')):
    original=file.read_text()
    backup=Path('/backups')/('jumper-pre-versioned-'+file.name)
    if not backup.exists():backup.write_text(original)
    def update(m):
        global total
        total+=1
        return f'{m.group("attr")}={m.group("quote")}{m.group("url")}?v={version}{m.group("quote")}'
    revised=regex.sub(update,original)
    if revised!=original:
        tmp=file.with_suffix(file.suffix+'.tmp')
        tmp.write_text(revised)
        os.replace(tmp,file)
assert total>=2,f'JUMPER_BUNDLE_REFERENCES_NOT_VERSIONED count={total}'
print('JUMPER_CACHE_BUST_VERSION='+version)
print('JUMPER_CACHE_BUST_REFERENCES='+str(total))
PY
