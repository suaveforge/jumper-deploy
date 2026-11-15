#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host --read-only \
  -v /home/suaveforge/secrets/spaceship.env:/run/spaceship.env:ro \
  python:3.11-alpine python - <<'PY'
from pathlib import Path
import urllib.request,urllib.error,json
env={}
for line in Path('/run/spaceship.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1);env[k.strip()]=v.strip().strip('"').strip("'")
key,secret=env.get('SPACESHIP_API_KEY'),env.get('SPACESHIP_API_SECRET')
if not key or not secret:raise RuntimeError('SPACESHIP_CREDENTIALS_MISSING')
host='jumper'; domain='suaveforge.com'; target='211.255.25.123'
base='https://spaceship.dev/api/v1/dns/records/'+domain
headers={'X-Api-Key':key,'X-Api-Secret':secret,'Accept':'application/json'}
def get():
    r=urllib.request.Request(base+'?take=500&skip=0',headers=headers)
    with urllib.request.urlopen(r,timeout=25) as f:obj=json.load(f)
    if isinstance(obj.get('items'),list): return obj['items']
    if isinstance(obj.get('records'),list): return obj['records']
    if isinstance(obj.get('data'),dict) and isinstance(obj['data'].get('items'),list):return obj['data']['items']
    raise RuntimeError('DNS_RESPONSE_UNKNOWN')
matches=lambda x:str(x.get('name','')).lower().rstrip('.') in (host,host+'.'+domain)
items=[r for r in get() if matches(r)]
if items:
    if any(str(r.get('type','')).upper()!='A' or str(r.get('address',''))!=target for r in items):
        raise RuntimeError('JUMPER_DNS_CONFLICT_REFUSE_OVERWRITE')
    print('JUMPER_DNS=ALREADY_SET')
else:
    data=json.dumps({'force':False,'items':[{'type':'A','name':host,'address':target,'ttl':600}]}).encode()
    req=urllib.request.Request(base,data=data,headers={**headers,'Content-Type':'application/json'},method='PUT')
    with urllib.request.urlopen(req,timeout=30) as r: print('JUMPER_DNS_WRITE_HTTP='+str(r.status))
verified=any(str(x.get('type','')).upper()=='A' and str(x.get('address',''))==target for x in get() if matches(x))
if not verified:raise RuntimeError('JUMPER_DNS_READBACK_FAILED')
print('JUMPER_DNS=VERIFIED')
print('JUMPER_URL=https://jumper.suaveforge.com')
PY
