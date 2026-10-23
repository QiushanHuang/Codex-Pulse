"""Keep local builds on a certificate identity. Never modify TCC or keychain ACLs."""
import json
from pathlib import Path
import re
import subprocess

try:
    from .input_continuity import compare, write_json
except ImportError:
    from input_continuity import compare, write_json

APP_ID = 'local.qiushan.CodexPulse'
PROFILE = Path.home() / 'Library/Application Support/CodexPulse/build-signing.json'


def available_identities():
    result = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'],
                            capture_output=True, text=True, check=True, timeout=15)
    return [{'sha1': match[0].upper(), 'name': match[1]} for match in
            re.findall(r'^\s*\d+\)\s+([0-9a-fA-F]{40})\s+"([^"\n]+)"', result.stdout, re.MULTILINE)]


def certificate_signed(signature):
    return bool(signature and signature.get('team') not in (None, '', 'not set', 'ad-hoc / 无 Team ID')
                and signature.get('requirement') and not signature['requirement'].startswith('cdhash '))


def load_profile(path=PROFILE):
    path = Path(path)
    if not path.exists():
        return None
    try:
        profile = json.loads(path.read_text())
        if (not isinstance(profile, dict) or profile.get('version') != 1
                or profile.get('identifier') != APP_ID or not certificate_signed(profile)
                or not isinstance(profile.get('sha1'), str)
                or not re.fullmatch('[0-9A-Fa-f]{40}', profile['sha1'])):
            raise ValueError('invalid profile')
        return profile
    except (OSError, ValueError, TypeError) as error:
        raise RuntimeError('本机固定签名配置不可读；为保留授权，不会退回临时签名。请检查 '+str(path)) from error


def select_signing_identity(requested=None, *, available, profile=None, installed=None, allow_change=False):
    if requested == '-':
        if not allow_change and (profile or certificate_signed(installed)):
            raise RuntimeError('已固定证书签名，不能改回临时签名；否则更新后会再次要求授权。')
        return {'sha1':'-', 'name':'Ad hoc'}
    if requested:
        matches = [i for i in available if requested.upper() == i['sha1'] or requested == i['name']]
        if len(matches) != 1:
            raise RuntimeError('指定的签名证书不可用或不唯一，请检查 security find-identity。')
        return matches[0]
    if profile:
        matches = [i for i in available if i['sha1'] == profile['sha1'].upper()]
        if len(matches) != 1:
            raise RuntimeError('固定签名证书当前不可用或已过期；不会自动换证书或退回临时签名。')
        return matches[0]
    eligible = [i for i in available if i['name'].startswith(('Apple Development:', 'Mac Developer:', 'Developer ID Application:'))]
    if len(eligible) == 1:
        return eligible[0]
    if len(eligible) > 1:
        raise RuntimeError('有多个可用签名身份，请用 --identity 指定一次，成功后会在本机固定。')
    if certificate_signed(installed):
        raise RuntimeError('已安装版本使用证书签名，但当前没有可用身份；不会退回临时签名。')
    # Fresh unsigned development/CI hosts can still build; an established signed
    # installation or profile can never silently take this fallback.
    return {'sha1':'-', 'name':'Ad hoc'}


def ensure_compatible(app, previous, *, allow_change=False):
    if not allow_change and certificate_signed(previous) and compare(app, previous) != 'matches':
        raise RuntimeError('候选版本不符合原有签名身份，已停止以保留输入监控授权。若确实要迁移身份，请显式使用 --allow-signing-change。')


def pin_identity(identity, signature, path=PROFILE):
    if identity['sha1'] == '-':
        return
    if not certificate_signed(signature) or signature['identifier'] != APP_ID:
        raise RuntimeError('没有取得有效证书签名，不能保存本机身份。')
    write_json(path, {'version':1, 'sha1':identity['sha1'], 'name':identity['name'], **signature})
