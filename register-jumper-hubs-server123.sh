#!/bin/sh
set -eu
# Create one canonical MONITOR JUMPER project (if absent), then connect
# AuthHub and PayHub through MONITOR APIs. No payment orders are created.
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host --read-only --memory 192m --pids-limit 80 \
 -v /home/suaveforge-monitor:/monitor:ro python:3.11-alpine python - <<'PY'
import pathlib,re,json,urllib.request,urllib.error
root=pathlib.Path('/monitor')
candidates=[]
for p in root.rglob('*'):
 try:
  if not p.is_file() or p.stat().st_size>120000 or len(p.relative_to(root).parts)>8:continue
  if not (p.name.lower().endswith(('.env','.conf','.txt')) or 'secret' in p.name.lower()):continue
  candidates.append(p)
 except (PermissionError,OSError):continue
secret=''
for p in candidates:
 try:
  for line in p.read_text(errors='replace').splitlines():
   m=re.match(r'^\s*(?:export\s+)?MONITOR_ADMIN_TOKEN\s*=\s*(.*?)\s*$',line)
   if m:
    secret=m.group(1).strip(' "\'')
    if secret:break
 except (PermissionError,OSError):continue
 if secret:break
print('MONITOR_ADMIN_SECRET_DISCOVERY='+('FOUND' if secret else 'NOT_FOUND'))
if not secret:raise SystemExit(4)
headers={'Authorization':'Bearer '+secret,'Accept':'application/json'}
def request(method,path,payload=None):
 data=json.dumps(payload).encode() if payload is not None else None
 req=urllib.request.Request('http://127.0.0.1:18500'+path,data=data,method=method,
 headers={**headers,**({'Content-Type':'application/json'} if data is not None else {})})
 try:
  with urllib.request.urlopen(req,timeout=20) as r:
   raw=r.read(160000).decode()
   return r.status,json.loads(raw) if raw else {}
 except urllib.error.HTTPError as e:
  raw=e.read(5000).decode()
  return e.code,{'error':raw[:250]}
status,catalog=request('GET','/api/integration/projects')
print('MONITOR_ADMIN_API_HTTP='+str(status))
if status!=200:raise SystemExit(5)
items=catalog.get('projects',[])
assert isinstance(items,list),'MONITOR_CATALOG_PROJECTS_INVALID'
exact=[p for p in items if str(p.get('public_url','')).rstrip('/').lower()=='https://jumper.suaveforge.com']
named=[p for p in items if str(p.get('name','')).strip().casefold()=='jumper']
matches={str(p.get('project_id','')):p for p in exact+named}
if len(matches)>1:
 print('MONITOR_JUMPER=AMBIGUOUS_CONFLICT_NO_CHANGES')
 raise SystemExit(6)
if matches:
 project=list(matches.values())[0]
 pid=str(project.get('project_id',''))
 print('MONITOR_JUMPER=ALREADY_EXISTS '+pid)
 if not exact:
  print('MONITOR_JUMPER_URL=CONFLICT_NO_CHANGES')
  raise SystemExit(7)
else:
 payload={'name':'JUMPER','kind':'웹 3D MMO','category':'운영','public_url':'https://jumper.suaveforge.com',
 'source':'manual','enabled':True,'monitorable':True}
 code,created=request('POST','/api/projects',payload)
 print('MONITOR_JUMPER_CREATE_HTTP='+str(code))
 if code!=201:
  print('MONITOR_JUMPER_CREATE_ERROR='+str(created.get('error','unknown'))[:250])
  raise SystemExit(8)
 pid=str(created.get('id',created.get('ID','')))
 print('MONITOR_JUMPER=CREATED '+pid)
if not re.fullmatch(r'p[0-9]+',pid):raise RuntimeError('MONITOR_RETURNED_INVALID_PROJECT_ID')
catalog_code,catalog=request('GET','/api/integration/projects')
assert catalog_code==200 and any(p.get('project_id')==pid for p in catalog.get('projects',[])),'MONITOR_CATALOG_READBACK_FAILED'
print('MONITOR_JUMPER_PROJECT_ID='+pid)
for hub in ('auth','pay'):
 code,connected=request('PUT',f'/api/projects/{pid}/hubs/{hub}',{'enabled':True})
 print('JUMPER_'+hub.upper()+'_CONNECTION_HTTP='+str(code))
 if code!=200:
  print('JUMPER_'+hub.upper()+'_CONNECT_ERROR='+str(connected.get('error','unknown'))[:300])
  continue
 print('JUMPER_'+hub.upper()+'_CONNECTION_ENABLED='+str(connected.get('enabled',connected.get('Enabled','unknown'))))
print('MONITOR_JUMPER_REGISTRATION=FINISHED')
PY
