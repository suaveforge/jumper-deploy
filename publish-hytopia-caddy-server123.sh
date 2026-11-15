#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host \
  -v /home:/home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import os,fcntl,subprocess
root=Path('/home/jumper')
main=Path('/home/gyeol/Caddyfile')
binary=Path('/home/gyeol/runtime/caddy/caddy')
snippet=root/'deploy/Caddyfile.jumper'
backup=root/'backups/Caddyfile.jumper.before-hytopia'
lock=root/'deploy/.caddy.lock'
if not all(p.is_file() for p in (main,binary,snippet)):
    raise RuntimeError('JUMPER_HYTOPIA_CADDY_FILES_MISSING')
fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
    old=snippet.read_text()
    if 'jumper.suaveforge.com' not in old:
        raise RuntimeError('JUMPER_EXPECTED_ROUTE_MISSING')
    if 'reverse_proxy 127.0.0.1:18772' not in old and 'retired' not in old.lower():
        raise RuntimeError('JUMPER_CADDY_CONFLICT_REFUSE_OVERWRITE')
    if not backup.exists():
        backup.write_text(old)
        os.chmod(backup,0o600)
    new='''# JUMPER prototype HYTOPIA browser, no Reldens process is exposed.
jumper.suaveforge.com {
    encode gzip zstd
    reverse_proxy 127.0.0.1:18772
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}
# The HYTOPIA source game server uses an in-repository local TLS certificate.
# Caddy terminates public TLS and talks to the backend over local loopback only.
api-jumper.suaveforge.com {
    encode gzip zstd
    @writes method POST PUT PATCH DELETE
    respond @writes "Evaluation API is read-only over HTTP" 403
    reverse_proxy https://127.0.0.1:18773 {
        transport http {
            tls_insecure_skip_verify
        }
    }
    header {
        X-Content-Type-Options "nosniff"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
}
'''
    if old != new:snippet.write_text(new)
    validation=subprocess.run([str(binary),'adapt','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=45)
    if validation.returncode:
        snippet.write_text(old)
        raise RuntimeError('JUMPER_HYTOPIA_CADDY_INVALID: '+validation.stderr.decode(errors='replace')[-750:])
    reload=subprocess.run([str(binary),'reload','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=60)
    if reload.returncode:
        snippet.write_text(old)
        subprocess.run([str(binary),'reload','--config',str(main),'--adapter','caddyfile'],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=35)
        raise RuntimeError('JUMPER_HYTOPIA_CADDY_RELOAD_FAILED_ROLLED_BACK: '+reload.stderr.decode(errors='replace')[-750:])
    print('JUMPER_HYTOPIA_CADDY=RELOADED')
finally:
    fcntl.flock(fd,fcntl.LOCK_UN)
    os.close(fd)
PY
