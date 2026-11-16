#!/bin/sh
set -eu
# Read-only: identify authoritative MONITOR JUMPER project and current Hub connections.
# Never print HUB_TOKEN, PayHub API/Webhook secrets, provider credentials, user data.
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host --read-only --memory 180m --pids-limit 80 \
 -v /home/authhub-runtime:/h-auth:ro \
 -v /home/payhub:/h-pay:ro \
 python:3.11-alpine python - <<'PY'
import os,re,json,pathlib,urllib.request,urllib.error
root=pathlib.Path('/h-auth')
files=[p for p in root.rglob('*') if p.is_file() and p.name in ('authhub.env','api.env','app.env','production.env')]
print('AUTHHUB_ENV_FILE_CANDIDATES='+str(len(files)))
token=''
for p in files:
 try:
  for line in p.read_text(errors='replace').splitlines():
   if line.startswith('HUB_TOKEN='):
    token=line.split('=',1)[1].strip().strip("'\"")
    if token:break
 except OSError:continue
 if token:break
def request(url,method='GET',body=None,auth=False):
 headers={'Accept':'application/json'}
 if auth and token:headers['Authorization']='Bearer '+token
 if body is not None:headers['Content-Type']='application/json'
 req=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,
    headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=12) as resp:
   return resp.status,json.loads(resp.read(70000).decode('utf8'))
 except urllib.error.HTTPError as e:
  return e.code,{'error':e.reason}
 except Exception as e:
  return 0,{'error':type(e).__name__}
for name,url in [('AuthHub health','https://api-authhub.suaveforge.com/health'),
 ('AuthHub JWKS','https://api-authhub.suaveforge.com/.well-known/jwks.json'),
 ('PayHub health','https://api-payhub.suaveforge.com/healthz')]:
 status,body=request(url)
 print(name.replace(' ','_').upper()+'_HTTP='+str(status))
 print(name.replace(' ','_').upper()+'_JSON='+str(isinstance(body,dict)))
if not token:
 print('MONITOR_CATALOG=UNAVAILABLE_HUB_TOKEN_NOT_FOUND')
 raise SystemExit(0)
code,body=request('https://api-monitor.suaveforge.com/api/integration/projects',auth=True)
print('MONITOR_CATALOG_HTTP='+str(code))
if code!=200:raise SystemExit(0)
items=body.get('projects',[]) if isinstance(body,dict) else []
matched=[x for x in items if 'jumper' in str(x.get('name','')).lower() or 'jumper.suaveforge.com' in str(x.get('public_url','')).lower() or '점퍼' in str(x.get('name',''))]
print('MONITOR_JUMPER_MATCH_COUNT='+str(len(matched)))
for x in matched:
 pid=x.get('project_id','')
 print('MONITOR_JUMPER='+json.dumps({k:x.get(k) for k in ('project_id','name','label','public_url','enabled')},ensure_ascii=False))
 if not re.fullmatch(r'p\d{2,}',str(pid)):continue
 for hub,base in [('AUTH','https://api-authhub.suaveforge.com'),('PAY','https://api-payhub.suaveforge.com')]:
  status,check=request(base+'/api/integration/projects/'+pid,auth=True)
  print(f'{hub}_JUMPER_INTEGRATION_HTTP='+str(status))
  if status==200:
   print(f'{hub}_JUMPER_INTEGRATION='+json.dumps({k:check.get(k) for k in ('project_id','name','connected','enabled')},ensure_ascii=False))
  if hub=='AUTH':
   code,conf=request(base+'/v1/config/'+pid+'?environment=production')
   print('AUTH_JUMPER_PUBLIC_CONFIG_HTTP='+str(code))
   if code==200: print('AUTH_JUMPER_PUBLIC_CONFIG='+json.dumps({k:conf.get(k) for k in ('project','environment','clientId','signupEnabled','approvalRequired','emailPasswordEnabled','providers')},ensure_ascii=False)[:2000])
PY

# Browser CORS is a real requirement for the shared AuthHub JS client.
req=urllib.request.Request(
 'https://api-authhub.suaveforge.com/v1/config/p51?environment=production',
 method='OPTIONS',
 headers={'Origin':'https://jumper.suaveforge.com','Access-Control-Request-Method':'GET'}
)
try:
 with urllib.request.urlopen(req,timeout=12) as resp:
  print('AUTH_JUMPER_BROWSER_CORS_HTTP='+str(resp.status))
  print('AUTH_JUMPER_BROWSER_CORS_ALLOWED='+str(resp.headers.get('Access-Control-Allow-Origin')=='https://jumper.suaveforge.com'))
except Exception as e:
 print('AUTH_JUMPER_BROWSER_CORS_FAILED='+str(type(e).__name__))
