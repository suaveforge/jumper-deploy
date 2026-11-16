#!/bin/sh
set -eu
# Read-only contract check for MONITOR p51, AuthHub and PayHub.
# Never print hub tokens, API keys, webhooks' secrets, user information or checkout credentials.
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network host --read-only --memory 180m --pids-limit 80 \
 -v /home/authhub-runtime:/h-auth:ro \
 python:3.11-alpine python - <<'PY'
import json, pathlib, urllib.request, urllib.error
root=pathlib.Path('/h-auth')
files=[p for p in root.rglob('*') if p.is_file() and p.name in ('authhub.env','api.env','app.env','production.env')]
print('AUTHHUB_ENV_FILE_CANDIDATES='+str(len(files)))
token=''
for p in files:
 try:
  for line in p.read_text(errors='replace').splitlines():
   if line.startswith('HUB_TOKEN='):
    token=line.split('=',1)[1].strip().strip("'\\"")
    if token: break
 except OSError: continue
 if token: break
def request(url,auth=False):
 headers={'Accept':'application/json'}
 if auth and token: headers['Authorization']='Bearer '+token
 req=urllib.request.Request(url,headers=headers,method='GET')
 try:
  with urllib.request.urlopen(req,timeout=12) as resp:
   raw=resp.read(100000).decode('utf-8')
   try: body=json.loads(raw)
   except json.JSONDecodeError: body=None
   return resp.status,body
 except urllib.error.HTTPError as e:
  return e.code,None
 except Exception as e:
  print('REQUEST_TRANSPORT_ERROR='+type(e).__name__)
  return 0,None
checks=[]
for name,url in (
 ('AUTHHUB_HEALTH','https://api-authhub.suaveforge.com/health'),
 ('AUTHHUB_JWKS','https://api-authhub.suaveforge.com/.well-known/jwks.json'),
 ('PAYHUB_HEALTH','https://api-payhub.suaveforge.com/healthz')):
 status,body=request(url)
 print(name+'_HTTP='+str(status))
 checks.append(status==200 and isinstance(body,dict))
if not token:
 print('HUB_TOKEN_DISCOVERY=NOT_FOUND')
 raise SystemExit(4)
code,catalog=request('https://api-monitor.suaveforge.com/api/integration/projects',auth=True)
print('MONITOR_CATALOG_HTTP='+str(code))
projects=catalog.get('projects',[]) if isinstance(catalog,dict) else []
matches=[x for x in projects if isinstance(x,dict) and x.get('project_id')=='p51'
 and x.get('name')=='JUMPER' and str(x.get('public_url','')).rstrip('/')=='https://jumper.suaveforge.com']
print('MONITOR_P51_MATCH_COUNT='+str(len(matches)))
checks.append(code==200 and len(matches)==1 and matches[0].get('enabled') is True if matches else False)
code,auth_projects=request('https://api-authhub.suaveforge.com/api/integration/projects',auth=True)
print('AUTHHUB_PROJECT_LIST_HTTP='+str(code))
auth_matches=[x for x in auth_projects if isinstance(x,dict) and x.get('project_id')=='p51'] if isinstance(auth_projects,list) else []
print('AUTHHUB_P51_MATCH_COUNT='+str(len(auth_matches)))
auth_active=len(auth_matches)==1 and auth_matches[0].get('connected') is True and auth_matches[0].get('enabled') is True
print('AUTHHUB_P51_CONNECTED='+str(auth_active))
checks.append(code==200 and auth_active)
code,conf=request('https://api-authhub.suaveforge.com/v1/config/p51?environment=production')
print('AUTHHUB_P51_PUBLIC_CONFIG_HTTP='+str(code))
if not isinstance(conf,dict): conf={}
is_p51=conf.get('project',{}).get('slug')=='p51' if isinstance(conf.get('project'),dict) else False
email_enabled=conf.get('emailPasswordEnabled') is True
providers=conf.get('providers',[]) if isinstance(conf.get('providers'),list) else []
print('AUTHHUB_P51_EMAIL_PASSWORD_ENABLED='+str(email_enabled))
print('AUTHHUB_P51_SOCIAL_PROVIDERS='+','.join(str(p) for p in providers) if providers else 'NONE')
auth_login_ready=code==200 and is_p51 and (email_enabled or bool(providers))
print('AUTHHUB_P51_LOGIN_METHOD_CONFIGURED='+str(auth_login_ready))
checks.append(auth_login_ready)
code,pay_response=request('https://api-payhub.suaveforge.com/api/integration/projects/p51',auth=True)
print('PAYHUB_P51_INTEGRATION_HTTP='+str(code))
pay_configured=isinstance(pay_response,dict) and pay_response.get('configured') is True
pay=pay_response.get('project',{}) if isinstance(pay_response,dict) else {}
pay=pay if isinstance(pay,dict) else {}
pay_connected=pay_configured and pay.get('project_id')=='p51' and pay.get('connected') is True and pay.get('enabled') is True
print('PAYHUB_P51_CONFIGURED='+str(pay_configured))
print('PAYHUB_P51_CONNECTED='+str(pay_connected))
pay_providers=pay.get('providers',[]) if isinstance(pay.get('providers'),list) else []
print('PAYHUB_P51_ENABLED_PROVIDERS='+','.join(str(x.get('id'))+':'+str(x.get('mode')) for x in pay_providers if isinstance(x,dict)) if pay_providers else 'NONE')
payment_ready=pay_connected and bool(pay_providers)
print('PAYHUB_P51_CHECKOUT_PROVIDER_READY='+str(payment_ready))
checks.append(code==200 and pay_connected)
checks.append(payment_ready)
print('JUMPER_LOGIN_END_TO_END=NOT_TESTED')
print('JUMPER_PAYMENT_END_TO_END=NOT_TESTED')
print('HUB_CONTRACT_CHECK='+('PASS' if all(checks) else 'FAIL'))
if not all(checks): raise SystemExit(2)
PY
