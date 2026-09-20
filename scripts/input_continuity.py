"""Code-signing evidence only. Never reads or changes TCC records."""
import json
from pathlib import Path
import subprocess
import time


def parse_signature(output):
    fields = dict(line.split('=', 1) for line in output.splitlines() if '=' in line)
    requirement = next((line.removeprefix('# ').removeprefix('designated => ') for line in output.splitlines()
                        if line.removeprefix('# ').startswith('designated => ')), '')
    if not fields.get('Identifier') or not fields.get('CDHash') or not requirement:
        return None
    return {'identifier': fields['Identifier'], 'cdhash': fields['CDHash'],
            'requirement': requirement, 'team': fields.get('TeamIdentifier', 'not set')}


def read_signature(app):
    result = subprocess.run(['/usr/bin/codesign', '-d', '-r-', '--verbose=4', str(app)],
                            capture_output=True, text=True, timeout=15)
    return parse_signature(result.stdout + result.stderr) if result.returncode == 0 else None


def compare(app, previous):
    if not previous:
        return 'unknown'
    result = subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '-R', '=' + previous['requirement'], str(app)],
                            capture_output=True, text=True, timeout=15)
    if result.returncode == 0:
        return 'matches'
    # Keep malformed signatures and tool failures distinct from a requirement mismatch.
    return 'changed' if 'failed to satisfy specified code requirement' in result.stderr else 'unknown'


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def status_matches(status, signature, since, app_path):
    return (isinstance(status, dict) and isinstance(status.get('at'), (int, float))
            and status['at'] >= since and status.get('appPath') == str(app_path)
            and isinstance(status.get('pid'), int) and status['pid'] > 0
            and isinstance(status.get('signature'), dict)
            and status['signature'].get('cdhash') == signature['cdhash']
            and status.get('state') in {'verified', 'disabled', 'signature_changed_denied',
                                        'permission_required', 'listener_failed'})


def build_report(app, installed, previous):
    current = read_signature(app)
    if not current:
        raise RuntimeError('无法读取新 app 的签名身份')
    return {'at': time.time(), 'appPath': str(app), 'installedPath': str(installed),
            'signature': current, 'previousSignature': previous,
            'continuity': compare(app, previous), 'authorization': 'requires_installed_app_runtime_check'}
