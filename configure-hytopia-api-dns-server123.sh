#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host --read-only \
 -v /home/suaveforge/secrets/spaceship.env:/run/spaceship.env:ro \
 python:3.11-alpine python - <<'PY'
from pathlib import Path
import urllib.request,urllib.error,json
keys={}
for line in Path('/run/spaceship.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v=line.split('=',1);keys[k.strip()]=v.strip().strip('"').strip("'")
key=keys.get('SPACESHIP_API_KEY')
secret=keys.get('SPACESHIP_API_SECRET')
if not key or not secret:raise RuntimeError('JUMPER_SPACESHIP_SECRET_MISSING')
domain='suaveforge.com'; host='api-jumper'; address='211.255.25.123'
base='https://spaceship.dev/api/v1/dns/records/'+domain
headers={'X-Api-Key':key,'X-Api-Secret':secret,'Accept':'application/json'}
def current():
    req=urllib.request.Request(base+'?take=500&skip=0',headers=headers)
    with urllib.request.urlopen(req,timeout=25) as response: data=json.load(response)
    if isinstance(data.get('items'),list):return data['items']
    if isinstance(data.get('records'),list):return data['records']
    if isinstance(data.get('data'),dict) and isinstance(data['data'].get('items'),list):return data['data']['items']
    raise RuntimeError('JUMPER_SPACESHIP_RESPONSE_UNRECOGNIZED')
def matches(r):
    name=str(r.get('name','')).lower().rstrip('.')
    return name in (host,host+'.'+domain)
entries=[r for r in current() if matches(r)]
if entries:
    if not all(str(r.get('type','')).upper()=='A' and str(r.get('address',''))==address for r in entries):
        raise RuntimeError('JUMPER_API_DNS_RECORD_CONFLICT_STOP')
    print('JUMPER_API_DNS=EXISTING_CORRECT')
else:
    body=json.dumps({'force':False,'items':[{'type':'A','name':host,'address':address,'ttl':600}]}).encode()
    req=urllib.request.Request(base,data=body,headers={**headers,'Content-Type':'application/json'},method='PUT')
    with urllib.request.urlopen(req,timeout=25) as response:
        print('JUMPER_API_DNS_UPDATE_HTTP='+str(response.status))
if not any(str(r.get('type','')).upper()=='A' and str(r.get('address',''))==address for r in current() if matches(r)):
    raise RuntimeError('JUMPER_API_DNS_READBACK_FAILED')
print('JUMPER_API_DNS=VERIFIED')
print('JUMPER_API_HOST=api-jumper.suaveforge.com')
PY
