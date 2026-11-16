#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
# Publish only /mini/* on the existing JUMPER hostname; preserve HYTOPIA
# front and API route. Validate global Caddyfile and rollback on failure.
"$D" -H "$S" run --rm -i --network host -v /home:/home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import os,re,fcntl,subprocess
root=Path('/home/jumper')
snippet=root/'deploy/Caddyfile.jumper'
main=Path('/home/gyeol/Caddyfile')
caddy=Path('/home/gyeol/runtime/caddy/caddy')
back=Path('/home/jumper-games/backup/Caddyfile.before-arcade')
lock=root/'deploy/.caddy.lock'
if not all(p.is_file() for p in (snippet,main,caddy)):
    raise RuntimeError('JUMPER_CADDY_FILES_MISSING')
fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
    old=snippet.read_text()
    m=re.search(r'(?ms)^jumper\.suaveforge\.com \{\n.*?^\}\n',old)
    if not m or '127.0.0.1:18772' not in m.group():
        raise RuntimeError('JUMPER_ORIGINAL_HYTOPIA_ROUTE_MISSING_REFUSE_PATCH')
    if not back.exists():
        back.parent.mkdir(parents=True,exist_ok=True)
        back.write_text(old)
        os.chmod(back,0o600)
    site='''jumper.suaveforge.com {
    encode gzip zstd
    handle_path /mini/* {
        reverse_proxy 127.0.0.1:18774
    }
    handle {
        reverse_proxy 127.0.0.1:18772 {
            header_up Host 127.0.0.1:18772
        }
    }
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}
'''
    newer=old[:m.start()]+site+old[m.end():]
    if newer==old:
        print('JUMPER_ARCADE_CADDY=ALREADY_ACTIVE')
    else:
        snippet.write_text(newer)
    check=subprocess.run([str(caddy),'adapt','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=35)
    if check.returncode:
        snippet.write_text(old)
        raise RuntimeError('JUMPER_ARCADE_CADDY_INVALID: '+check.stderr.decode(errors='replace')[-800:])
    reload=subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=50)
    if reload.returncode:
        snippet.write_text(old)
        subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=35)
        raise RuntimeError('JUMPER_ARCADE_CADDY_ROLLED_BACK: '+reload.stderr.decode(errors='replace')[-800:])
    print('JUMPER_ARCADE_CADDY=RELOADED')
finally:
    fcntl.flock(fd,fcntl.LOCK_UN)
    os.close(fd)
PY
