#!/bin/sh
set -eu
D=/home/ggul-docker/bin/docker
S=unix:///home/ggul-docker/run/docker.sock
"$D" -H "$S" run --rm -i --network none \
  -v /home/jumper/app:/app:rw -v /home/jumper/backups:/backups:rw \
  python:3.11-alpine python - <<'PY'
from pathlib import Path
import re,os
source=Path('/app/theme/default/index.html')
assert source.is_file(), 'JUMPER_THEME_NOT_FOUND'
old=source.read_text()
backup=Path('/backups/reldens-original-lobby-index.html')
if not backup.exists():backup.write_text(old)
if 'id="jumper-lobby-style"' in old:
    print('JUMPER_LOBBY_BRANDING=ALREADY_STAGED')
    raise SystemExit(0)
assert '<div class="header-content">' in old,'JUMPER_HEADER_SHAPE_UNRECOGNIZED'
assert '<form name="register-form"' in old,'JUMPER_REGISTER_FORM_NOT_FOUND'
assert '<form name="guest-form"' in old,'JUMPER_GUEST_FORM_NOT_FOUND'
html=old
html=html.replace('<title>Reldens | MMORPG Platform | By DwDeveloper</title>',
                  '<title>JUMPER | 함께 만들고 배우는 월드</title>')
html=html.replace('content="Reldens, an open source MMORPG platform"',
                  'content="JUMPER: 유저가 직접 만들고 함께 배우는 멀티플레이 월드"')
html=html.replace('<div class="header-content">\n                <img id="your-logo" src="./assets/web/reldens-your-logo-mage.png" alt="reldens"/>\n                <h1 class="title">\n                    - <strong>reldens</strong> <span id="current-version">demo -</span>\n                    <br/>- your logo here -\n                </h1>\n            </div>',
'''<div class="header-content">
                <div class="jumper-mark" aria-hidden="true">J</div>
                <div class="jumper-brand">
                    <h1 class="title">JUMPER</h1>
                    <p>함께 만들고, 함께 배우는 월드</p>
                </div>
                <span id="current-version" class="jumper-engine-version" aria-hidden="true"></span>
            </div>''')
assert '<div class="jumper-mark"' in html,'JUMPER_HEADER_REPLACE_FAILED'
# Preserve the upstream .row-disclaimer hook for the game engine, but hide the demo text.
html=html.replace('Disclaimer: Reldens is not just a game, is a platform to create games.', '')
html=html.replace('This is a demo to show how many features are available on the platform.', '')
replacements={
    '<h3 class="form-title">Login</h3>':'<h3 class="form-title">로그인</h3>',
    '<h3 class="form-title">Create Account</h3>':'<h3 class="form-title">회원가입</h3>',
    '<h3 class="form-title">Play as a Guest</h3>':'<h3 class="form-title">바로 시작하기</h3>',
    'value="Submit"':'value="로그인"',
    'value="Play"':'value="게스트로 시작"',
    'value="Register"':'value="가입하고 시작"',
    'placeholder="Username"':'placeholder="아이디"',
    'placeholder="Password"':'placeholder="비밀번호"',
    'placeholder="Re-type Password"':'placeholder="비밀번호 확인"',
    'placeholder="Email"':'placeholder="이메일"',
    'placeholder="Re-type password"':'placeholder="비밀번호 확인"',
    'placeholder="Guest Name"':'placeholder="게스트 이름"',
    'alt="reldens"':'alt="JUMPER"'
}
for a,b in replacements.items():html=html.replace(a,b)
css=r"""
body:not(.game-engine-started) {font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;}
body:not(.game-engine-started) .wrapper {background:#152438;min-height:100vh;justify-content:flex-start;overflow:auto;}
body:not(.game-engine-started) .wrapper .header {height:auto;min-height:0;flex-grow:0;padding:64px 20px 38px;background:transparent;}
body:not(.game-engine-started) .header .header-content {max-width:960px;width:100%;display:flex;flex-wrap:nowrap;align-items:center;gap:18px;justify-content:center;}
body:not(.game-engine-started) .jumper-mark {display:grid;place-items:center;flex:none;width:65px;height:65px;background:#f1f6fc;color:#193453;border-radius:16px;font-size:36px;font-weight:850;letter-spacing:-.08em;}
body:not(.game-engine-started) .jumper-brand h1.title {font:800 43px/1.05 system-ui,-apple-system,sans-serif;letter-spacing:-.045em;color:#fff;margin:0;}
body:not(.game-engine-started) .jumper-brand p {font-size:17px;line-height:1.4;margin:9px 0 0;color:#b8c9e0;}
body:not(.game-engine-started) .jumper-engine-version {display:none;}
body:not(.game-engine-started) .wrapper .content {width:100%;height:auto;min-height:0;flex-grow:1;max-width:1040px;margin:0 auto;padding:0 24px 35px;}
body:not(.game-engine-started) .content .row-disclaimer {display:none;}
body:not(.game-engine-started) .content .forms-container {max-width:940px;height:auto;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px;align-items:start;}
body:not(.game-engine-started) .content .col-2 {display:flex;flex-direction:column;flex-wrap:nowrap;align-items:stretch;gap:18px;min-width:0;width:100%;}
body:not(.game-engine-started) .content .row.wooden-box {width:100%;max-width:none;padding:0;margin:0;background:#fff;border:1px solid #e2e9f2;border-radius:17px;overflow:hidden;box-shadow:0 12px 28px rgba(4,12,25,.2);}
body:not(.game-engine-started) .content .wooden-box::before {display:none;}
body:not(.game-engine-started) .content h3.form-title {font-size:22px;font-weight:750;text-align:left;line-height:1.3;padding:25px 30px 20px;background:#fff;color:#172539;border:0;margin:0 0 6px;}
body:not(.game-engine-started) .content form {width:100%;margin:0;padding:0 30px 28px;}
body:not(.game-engine-started) .content form .input-box {width:100%;margin-bottom:12px;display:flex;align-items:stretch;}
body:not(.game-engine-started) .content form .input-box input[type=text],
body:not(.game-engine-started) .content form .input-box input[type=email],
body:not(.game-engine-started) .content form .input-box input[type=password] {
 display:block;width:100%;max-width:none;min-width:0;height:47px;padding:12px 14px;border:1px solid #d0d9e6;border-radius:9px;background:#f8fafc;color:#18283e;font-size:16px;font-weight:500;box-shadow:none;outline-offset:1px;
}
body:not(.game-engine-started) .content form .input-box input:focus-visible {outline:2px solid #2d74d7;border-color:#2d74d7;background:#fff;}
body:not(.game-engine-started) .content form .submit-container {display:flex;width:100%;align-items:stretch;justify-content:center;margin:15px 0 0;}
body:not(.game-engine-started) .content form input[type=submit] {
 display:block;width:100%;height:47px;border:0;border-radius:9px;background:#2465ba;color:white;font-size:16px;font-weight:750;box-shadow:none;cursor:pointer;
}
body:not(.game-engine-started) .content form input[type=submit]:hover {background:#194c91;}
body:not(.game-engine-started) .content form input[type=submit]:focus-visible {outline:3px solid #8db5ff;outline-offset:2px;}
body:not(.game-engine-started) .content .guest-form input[type=submit] {background:#1a705d;}
body:not(.game-engine-started) .content .guest-form input[type=submit]:hover {background:#145344;}
body:not(.game-engine-started) .content .response-error {font-size:14px;font-weight:650;line-height:1.45;text-align:left;color:#ba3131;background:#fff3f3;box-shadow:none;padding:12px 14px;border-radius:9px;margin-top:12px;}
body:not(.game-engine-started) .content .response-error:empty {display:none;}
body:not(.game-engine-started) .content .terms-and-conditions-link-container {font-size:14px;line-height:1.45;}
body:not(.game-engine-started) .content .terms-and-conditions-link-container p {color:#305f9b;text-decoration:underline;cursor:pointer;}
body:not(.game-engine-started) .wrapper .footer {display:flex;flex:0 0 auto;min-height:50px;padding:16px 0 25px;background:transparent;}
body:not(.game-engine-started) .wrapper .footer .copyright {opacity:.65;font-size:12px;}
body:not(.game-engine-started) .wrapper .footer .copyright a {color:#d4e0ef;text-decoration:none;}
@media (max-width:730px) {
 body:not(.game-engine-started) .wrapper .header {padding:34px 18px 28px;}
 body:not(.game-engine-started) .header .header-content {justify-content:flex-start;gap:13px;}
 body:not(.game-engine-started) .jumper-mark {width:50px;height:50px;border-radius:12px;font-size:27px;}
 body:not(.game-engine-started) .jumper-brand h1.title {font-size:32px;}
 body:not(.game-engine-started) .jumper-brand p {font-size:14px;margin-top:5px;}
 body:not(.game-engine-started) .wrapper .content {padding:0 16px 22px;}
 body:not(.game-engine-started) .content .forms-container {grid-template-columns:1fr;gap:18px;}
 body:not(.game-engine-started) .content .col-2 {width:100%;margin:0;gap:18px;}
 body:not(.game-engine-started) .content h3.form-title {font-size:20px;padding:22px 22px 15px;}
 body:not(.game-engine-started) .content form {padding:0 22px 22px;}
 body:not(.game-engine-started) .wrapper .footer {padding:12px;}
}
"""
assert '</head>' in html,'JUMPER_HEAD_NOT_FOUND'
html=html.replace('</head>','<style id="jumper-lobby-style">\n'+css+'\n</style>\n</head>',1)
tmp=source.with_name('.index.html.jumper-patch')
tmp.write_text(html)
os.replace(tmp,source)
print('JUMPER_LOBBY_BRANDING=STAGED')
PY
