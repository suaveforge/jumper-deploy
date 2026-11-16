#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host -v /home:/home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,os,fcntl,subprocess
root=Path('/home/jumper')
snippet=root/'deploy/Caddyfile.jumper'
main=Path('/home/gyeol/Caddyfile')
exe=Path('/home/gyeol/runtime/caddy/caddy')
back=Path('/home/jumper-hubs/backup/Caddyfile.before-hub-gateway')
lock=root/'deploy/.caddy.lock'
if not all(p.is_file() for p in (snippet,main,exe)):
 raise RuntimeError('JUMPER_SHARED_PROXY_FILES_UNAVAILABLE')
fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
 old=snippet.read_text()
 m=re.search(r'(?ms)^jumper\.suaveforge\.com \{\n.*?^\}\n',old)
 if not m or '127.0.0.1:18772' not in m.group():
  raise RuntimeError('JUMPER_PUBLIC_3D_PROXY_UNEXPECTED')
 site=m.group()
 routes='''    handle /hub-auth/* {
        reverse_proxy 127.0.0.1:18777
    }
    handle /api/jumper/* {
        reverse_proxy 127.0.0.1:18777
    }
    handle /api/hub/events {
        reverse_proxy 127.0.0.1:18777
    }
'''
 if 'handle /hub-auth/*' not in site:
  if '    encode gzip zstd\n' not in site:
   raise RuntimeError('JUMPER_CADDY_ENCODE_ANCHOR_MISSING')
  site=site.replace('    encode gzip zstd\n','    encode gzip zstd\n'+routes,1)
 if not back.exists():
  back.parent.mkdir(parents=True,exist_ok=True)
  back.write_text(old)
  os.chmod(back,0o600)
 new=old[:m.start()]+site+old[m.end():]
 if new!=old:snippet.write_text(new)
 check=subprocess.run([str(exe),'adapt','--config',str(main),'--adapter','caddyfile'],
 stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=40)
 if check.returncode:
  snippet.write_text(old)
  raise RuntimeError('JUMPER_HUB_CADDY_SYNTAX_FAIL '+check.stderr.decode(errors='replace')[-400:])
 reload=subprocess.run([str(exe),'reload','--config',str(main),'--adapter','caddyfile'],
 stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=60)
 if reload.returncode:
  snippet.write_text(old)
  subprocess.run([str(exe),'reload','--config',str(main),'--adapter','caddyfile'],
   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
  raise RuntimeError('JUMPER_HUB_CADDY_RELOAD_ROLLED_BACK')
 print('JUMPER_AUTHHUB_PAYHUB_HTTPS_ROUTES=VERIFIED')
finally:
 fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
PY
