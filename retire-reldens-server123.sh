#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock

# The existing public hostname stays reserved for the replacement JUMPER.
# Replace only the imported Jumper vhost, not the shared Caddyfile or other apps.
"$D" -H "$S" run --rm -i --network host \
  -v /home:/home:rw python:3.11-alpine python - <<'PY'
from pathlib import Path
import fcntl, os, shutil, subprocess
root=Path('/home/jumper')
snippet=root/'deploy/Caddyfile.jumper'
caddy=Path('/home/gyeol/runtime/caddy/caddy')
main=Path('/home/gyeol/Caddyfile')
backup=root/'backups/Caddyfile.jumper.reldens-before-retirement'
lock=root/'deploy/.caddy.lock'
if not main.is_file() or not caddy.is_file() or not snippet.is_file():
    raise RuntimeError('JUMPER_CADDY_CONFIG_NOT_FOUND_REFUSE_UNSAFE_CHANGE')
fd=os.open(lock,os.O_CREAT|os.O_RDWR,0o600)
fcntl.flock(fd,fcntl.LOCK_EX)
try:
    old=snippet.read_text()
    if not backup.exists():
        backup.parent.mkdir(parents=True,exist_ok=True)
        backup.write_text(old)
        os.chmod(backup,0o600)
    newer='''# Legacy Reldens is retired. Keep this hostname for the next JUMPER engine.
jumper.suaveforge.com {
    respond "JUMPER: the old Reldens demo has been retired." 410
}
'''
    if old != newer:
        snippet.write_text(newer)
    check=subprocess.run([str(caddy),'adapt','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=35)
    if check.returncode:
        snippet.write_text(old)
        raise RuntimeError('JUMPER_CADDY_VALIDATE_FAILED: '+check.stderr.decode(errors='replace')[-600:])
    reload=subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
        stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=45)
    if reload.returncode:
        snippet.write_text(old)
        subprocess.run([str(caddy),'reload','--config',str(main),'--adapter','caddyfile'],
            stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
        raise RuntimeError('JUMPER_CADDY_RELOAD_FAILED_ROLLED_BACK: '+reload.stderr.decode(errors='replace')[-600:])
    print('RELDENS_PUBLIC_ROUTE=RETIRED_410')
finally:
    fcntl.flock(fd,fcntl.LOCK_UN)
    os.close(fd)
PY

# Do not delete the app, database or volumes: preserve for audit/rollback.
# Disable restart before stopping. Touch only the two names below.
for name in sf-jumper sf-jumper-db; do
  if "$D" -H "$S" inspect "$name" >/dev/null 2>&1; then
    "$D" -H "$S" update --restart=no "$name" >/dev/null
    "$D" -H "$S" stop -t 18 "$name" >/dev/null || true
    state=$("$D" -H "$S" inspect --format '{{.State.Running}}' "$name")
    policy=$("$D" -H "$S" inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$name")
    echo "CONTAINER_$name=$state RESTART_POLICY=$policy"
    [ "$state" = false ] && [ "$policy" = no ] || exit 1
  else
    echo "CONTAINER_$name=NOT_FOUND"
  fi
done

# Check the externally exposed old application is not serving.
code=$(curl -sS --max-time 20 --resolve jumper.suaveforge.com:443:127.0.0.1 \
  -o /tmp/jumper-legacy-retired-body -w '%{http_code}' https://jumper.suaveforge.com/)
[ "$code" = 410 ] || { echo "RELDENS_RETIREMENT_UNVERIFIED HTTP=$code"; exit 1; }
if grep -Eqi '(game-container|<form|<canvas)' /tmp/jumper-legacy-retired-body; then
  echo RELDENS_FRONTEND_STILL_EXPOSED
  exit 1
fi
echo "RELDENS_RETIRED=VERIFIED HTTP=410"
