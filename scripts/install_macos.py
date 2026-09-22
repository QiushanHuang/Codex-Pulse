#!/usr/bin/env python3
"""Explicit local installation with signature receipts and runtime verification."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

try:
    from .input_continuity import read_signature, build_report, write_json, status_matches
except ImportError:
    from input_continuity import read_signature, build_report, write_json, status_matches

ROOT = Path(__file__).resolve().parent.parent
TARGET = Path('/Applications/Codex Pulse.app')
DATA = Path.home() / 'Library/Application Support/CodexPulse'


def remove_widget_registration(extension):
    result = subprocess.run(['/usr/bin/pluginkit', '-r', str(extension)], capture_output=True, text=True)
    if result.returncode and not (result.returncode == 1 and
            result.stderr.strip() == f'remove: no plugin at {extension}'):
        result.check_returncode()
    return result.returncode == 0


def refresh_widget_registration(source_app=None):
    """Refresh only Pulse registrations; leave other widgets and their caches alone."""
    extension = Path('Contents/PlugIns/CodexPulseWidget.appex')
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    if source_app is not None and source_app.resolve() != TARGET.resolve():
        if remove_widget_registration(source_app / extension):
            subprocess.run([lsregister, '-u', str(source_app)], check=True)
    # Removing the old extension registration retires its cached process/version.
    # Re-add the installed extension only after its host registration is current.
    remove_widget_registration(TARGET / extension)
    subprocess.run([lsregister, '-f', str(TARGET)], check=True)
    subprocess.run(['/usr/bin/pluginkit', '-a', str(TARGET / extension)], check=True)


def install(app):
    app = app.resolve()
    if app == TARGET:
        raise RuntimeError('构建来源不能是安装目标')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = read_signature(app)
    if not signature or signature['identifier'] != 'local.qiushan.CodexPulse':
        raise RuntimeError('不是有效的 Codex Pulse 构建')
    # Refuse to replace a running executable. Quit in the app first so it flushes settings.
    if subprocess.run(['/usr/bin/pgrep', '-x', 'CodexPulse'], capture_output=True).returncode == 0:
        raise RuntimeError('请先在 Codex Pulse 中退出，再重新安装；当前安装尚未替换')
    receipt = build_report(app, TARGET, read_signature(TARGET))
    stamp = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:6]
    backup = ROOT / 'build/backups' / ('Codex-Pulse-before-input-continuity-' + stamp) / 'Codex Pulse.app'
    backup.parent.mkdir(parents=True, exist_ok=True)
    # Keep staging outside /Applications and preserve the canonical app filename.
    stage = ROOT / 'build/.install-staging' / stamp / 'Codex Pulse.app'
    stage.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app, stage)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
    if TARGET.exists():
        TARGET.rename(backup)
        receipt['backupPath'] = str(backup)
    try:
        stage.rename(TARGET)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(TARGET)], check=True)
    except Exception:
        # Preserve the failed replacement as evidence and restore the previous app.
        if TARGET.exists():
            TARGET.rename(stage)
        if backup.exists():
            backup.rename(TARGET)
        raise
    refresh_widget_registration(app)
    receipt['widgetRegistration'] = 'refreshed'
    receipt['installedAt'] = time.time()
    receipt_path = ROOT / 'build' / ('input-install-' + stamp + '.json')
    write_json(receipt_path, receipt)
    subprocess.run(['/usr/bin/open', str(TARGET)], check=True)
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        try:
            status = json.loads((DATA / 'input-status.json').read_text())
            if status_matches(status, signature, receipt['installedAt'], TARGET):
                os.kill(status['pid'], 0)
                receipt['runtime'] = status
                write_json(receipt_path, receipt)
                print('已安装并验证状态显示数据：' + status['status'])
                print('签名连续性：' + status['continuity'])
                print('记录：' + str(receipt_path))
                return receipt
        except (OSError, ValueError):
            pass
        time.sleep(0.5)
    raise RuntimeError('已安装，但未取得新 app 的有效状态；请检查 app。安装记录：' + str(receipt_path))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/Codex Pulse.app')
    parser.add_argument('--repair-widget', action='store_true', help='Refresh only the installed Widget registration without replacing the app')
    args = parser.parse_args()
    if args.repair_widget:
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(TARGET)], check=True)
        refresh_widget_registration(args.app)
        print('已刷新 Codex Pulse 小组件注册；macOS 将重新加载时间线。')
    else:
        install(args.app)
