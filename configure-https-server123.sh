#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host -v /home:/home:rw python:3.11-alpine python - <<'PY'
import os,subprocess,fcntl,shutil,stat
from pathlib import Path
root=Path('/home/jumper')
(root/'deploy').mkdir(parents=True,exist_ok=True)
(root/'backups').mkdir(parents=True,exist_ok=True)
caddy=Path('/home/gyeol/runtime/caddy/caddy')
main=Path('/home/gyeol/Caddyfile')
snippet=root/'deploy/Caddyfile.jumper'
line='import /home/jumper/deploy/Caddyfile.jumper'
lock=root/'deploy/.caddy.lock'
if not caddy.is_file() or not main.is_file():
    raise RuntimeError('JUMPER_SHARED_CADDY_MISSING')
text='''# Jumper isolated browser MMO. Backend only listens on loopback.
jumper.suaveforge.com {
    encode gzip zstd
    reverse_proxy 127.0.0.1:18766
    # Versioned Parcel files may keep identical URLs across regenerations.
    # Revalidate the lobby, JS/CSS and config on every navigation instead
    # of allowing a pre-install config and fresh HTML to be mixed by browsers.
    @browserApp {
        path / /index.html *.html *.js *.css *.json
    }
    header @browserApp >Cache-Control "no-cache, max-age=0, must-revalidate"
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}
'''
fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
    old=main.read_bytes()
    original_snippet=snippet.read_text() if snippet.exists() else None
    snippet.write_text(text)
    candidate=old if line.encode() in old else old.rstrip()+b'\n\n'+line.encode()+b'\n'
    temp=main.parent/'.Caddyfile.jumper.candidate'
    temp.write_bytes(candidate)
    shutil.copymode(main,temp)
    adapt=subprocess.run([str(caddy),'adapt','--config',str(temp),'--adapter','caddyfile'],
                         stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=30)
    if adapt.returncode:
        temp.unlink(missing_ok=True)
        if original_snippet is None: snippet.unlink(missing_ok=True)
        else: snippet.write_text(original_snippet)
        raise RuntimeError('JUMPER_CADDY_VALIDATION_FAILED: '+adapt.stderr.decode(errors='replace')[:500])
    backup=root/'backups/Caddyfile.before-jumper'
    if candidate!=old and not backup.exists():
        backup.write_bytes(old)
        os.chmod(backup,0o600)
    if candidate!=old: os.replace(temp,main)
    else: temp.unlink(missing_ok=True)
    reload=subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
                          stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=40)
    if reload.returncode:
        if candidate!=old:
            restore=main.parent/'.Caddyfile.jumper.rollback'
            restore.write_bytes(old)
            shutil.copymode(main,restore)
            os.replace(restore,main)
            subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
                           stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
        if original_snippet is None: snippet.unlink(missing_ok=True)
        else: snippet.write_text(original_snippet)
        raise RuntimeError('JUMPER_CADDY_RELOAD_FAILED_ROLLED_BACK')
    print('JUMPER_CADDY=RELOADED')
finally:
    fcntl.flock(fd,fcntl.LOCK_UN)
    os.close(fd)
PY
