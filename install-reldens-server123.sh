#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
ROOT=/home/jumper
"$D" -H "$S" run --rm --network host \
  -v "$ROOT/secrets:/run/jumper-secrets:ro" \
  -v "$ROOT/app:/app:rw" \
  python:3.11-alpine python - <<'PY'
import os,time,urllib.request,urllib.parse,urllib.error
from pathlib import Path
base='http://127.0.0.1:18766'
lock=Path('/app/install.lock')
if lock.exists():
    print('JUMPER_RELDENS_INSTALL=ALREADY_DONE')
    raise SystemExit(0)
def env(path):
    out={}
    for line in Path(path).read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1)
            out[k.strip()]=v.strip()
    return out
db=env('/run/jumper-secrets/db.env')
secrets=env('/run/jumper-secrets/app-secrets.env')
for attempt in range(100):
    try:
        with urllib.request.urlopen(base+'/', timeout=5) as r:
            if r.status==200:
                break
    except Exception as e:
        if attempt==99: raise RuntimeError('JUMPER_INSTALLER_UNREACHABLE: '+str(e))
    time.sleep(3)
else: raise RuntimeError('JUMPER_INSTALLER_NOT_READY')
form={
 'app-host':'http://0.0.0.0','app-port':'8080',
 'app-public-url':'https://jumper.suaveforge.com',
 'app-trusted-proxy':'1',
 'app-admin-path':'/reldens-admin',
 'app-admin-secret':secrets['JUMPER_ADMIN_SECRET'],
 'app-signed-tokens-secret':secrets['JUMPER_SIGN_SECRET'],
 'app-admin-hot-plug':'1',
 'app-allow-packages-installation':'1',
 'app-use-https':'0','app-use-monitor':'0','app-secure-monitor':'0',
 'db-storage-driver':'knex','db-client':'mysql2',
 'db-host':'sf-jumper-db','db-port':'3306','db-name':'jumper',
 'db-username':db['MARIADB_USER'],'db-password':db['MARIADB_PASSWORD'],
 'db-basic-config':'1','db-sample-data':'1',
 'mailer-service':'none','mailer-enable':'0',
 'firebase-enable':'0',
}
req=urllib.request.Request(base+'/install',data=urllib.parse.urlencode(form).encode(),method='POST')
try:
    with urllib.request.urlopen(req,timeout=300) as r:
        print('JUMPER_INSTALL_HTTP='+str(r.status))
        print('JUMPER_INSTALL_FINAL_PATH='+urllib.parse.urlsplit(r.url).path)
except urllib.error.HTTPError as e:
    raise RuntimeError('JUMPER_INSTALL_HTTP_ERROR_'+str(e.code))
if not lock.exists():
    raise RuntimeError('JUMPER_RELDENS_INSTALL_FAILED_NO_LOCK')
print('JUMPER_RELDENS_INSTALL=VERIFIED')
PY
