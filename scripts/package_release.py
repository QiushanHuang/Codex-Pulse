#!/usr/bin/env python3
"""Package a built arm64 app with pinned, relocatable runtimes. Never installs it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '2.1.3'
RUNTIMES = {
    'python': {
        'version': '3.13.15',
        'url': 'https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.13.15%2B20260901-aarch64-apple-darwin-install_only.tar.gz',
        'sha256': 'b9054a9d3d54f4cb5573d44907fddb29874b08909bde73f29f2868cf872223ee',
        'folder': 'python',
    },
    'node': {
        'version': '22.23.2',
        'url': 'https://nodejs.org/dist/v22.23.2/node-v22.23.2-darwin-arm64.tar.gz',
        'sha256': '61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6',
        'folder': 'node-v22.23.2-darwin-arm64',
    },
}


def run(*args, **kwargs):
    subprocess.run([str(a) for a in args], check=True, **kwargs)


def sha256(path):
    with Path(path).open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
        return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/Codex Pulse.app')
    parser.add_argument('--widget', type=Path, help='Optional freshly built extension to replace the source build extension')
    parser.add_argument('--downloads', type=Path, default=ROOT / 'build/release/downloads')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/release/v2.1.3')
    args = parser.parse_args()
    if os.uname().machine != 'arm64':
        raise SystemExit('This pinned release recipe is for Apple Silicon only.')
    if args.output.exists():
        raise SystemExit('Output exists; choose a new --output to preserve previous artifacts.')
    source_info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    if source_info['CFBundleShortVersionString'] != VERSION:
        raise SystemExit('Build version does not match this release recipe.')
    run('codesign', '--verify', '--deep', '--strict', args.app)
    args.downloads.mkdir(parents=True, exist_ok=True)
    for name, spec in RUNTIMES.items():
        archive = args.downloads / f'{name}.tar.gz'
        if not archive.exists():
            urllib.request.urlretrieve(spec['url'], archive)
        if sha256(archive) != spec['sha256']:
            raise SystemExit(f'{name} archive SHA-256 mismatch; refusing extraction.')
    args.output.mkdir(parents=True)
    stage = args.output / 'stage'
    stage.mkdir()
    app = stage / 'Codex Pulse.app'
    shutil.copytree(args.app, app, symlinks=True)
    resources = app / 'Contents/Resources'
    extension = app / 'Contents/PlugIns/CodexPulseWidget.appex'
    if args.widget:
        shutil.rmtree(extension)
        shutil.copytree(args.widget, extension, symlinks=True)
    widget_info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
    if widget_info['CFBundleShortVersionString'] != VERSION:
        raise SystemExit('Fresh widget version must match the app version.')
    # Never distribute this machine's signing/authorization history.
    (resources / 'input-install-baseline.json').unlink(missing_ok=True)
    runtime = resources / 'runtime'
    runtime.mkdir(exist_ok=False)
    unpack = args.output / 'unpack'
    unpack.mkdir()
    for name, spec in RUNTIMES.items():
        with tarfile.open(args.downloads / f'{name}.tar.gz') as archive:
            # Requires Python 3.12+ for the release builder, not for running the app.
            archive.extractall(unpack, filter='data')
        shutil.move(str(unpack / spec['folder']), runtime / name)
    # Embed the current backend source, excluding local bytecode.
    backend = resources / 'backend'
    shutil.rmtree(backend)
    for name in ('codex_pulse', 'scripts'):
        shutil.copytree(ROOT / name, backend / name,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    docs = resources / 'Documentation'
    docs.mkdir(exist_ok=True)
    for name in ('README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CONTRIBUTORS.md', 'CHANGELOG.md'):
        shutil.copy2(ROOT / name, docs / name)
    # Preserve relative links in the offline documentation.
    for name in ('docs/user-guide.md', 'docs/troubleshooting.md', 'docs/building.md',
                 'CONTRIBUTING.md', 'docs/releases/v2.1.3.md', 'docs/releases/release-validation.md'):
        destination = docs / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    for name in ('docs/third-party', 'docs/images'):
        shutil.copytree(ROOT / name, docs / name)
    branding = docs / 'assets/branding'
    branding.mkdir(parents=True)
    for name in ('logo.svg', 'banner.svg'):
        shutil.copy2(ROOT / 'assets/branding' / name, branding / name)
    info = {**source_info, 'PulsePython': 'runtime/python/bin/python3', 'PulseNode': 'runtime/node/bin/node'}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    manifest = {'version': VERSION, 'architecture': 'arm64', 'minimum_macos': '14.0',
                'signing': 'ad-hoc', 'notarized': False, 'runtimes': RUNTIMES}
    (resources / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Sign each actual Mach-O once, then the nested extension, then the outer app.
    magic = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    for path in sorted(runtime.rglob('*')):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                macho = stream.read(4) in magic
            if macho:
                run('codesign', '--force', '--sign', '-', path)
    run('codesign', '--force', '--sign', '-', extension)
    run('codesign', '--force', '--sign', '-', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'}
    env.pop('PYTHONHOME', None)
    env.pop('PYTHONPATH', None)
    run(runtime / 'python/bin/python3', '-I', '-B', '-c',
        'import ssl, sqlite3, ctypes, bz2, lzma; print("Bundled Python imports OK")', env=env)
    run(runtime / 'node/bin/node', '--input-type=module', '-e',
        'if(typeof WebSocket !== "function") throw Error("WebSocket missing"); console.log("Bundled Node WebSocket OK")', env=env)
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'START-HERE.txt').write_text(
        'Codex Pulse 2.1.3 — Apple Silicon / macOS 14+\n\n'
        'Drag Codex Pulse.app to Applications. Python and Node.js are included.\n'
        'Install and sign in to Codex separately. G HUB is optional for keyboard lighting.\n'
        'Ad-hoc signed; NOT Apple-notarized. Read the first-launch instructions:\n'
        'https://github.com/QiushanHuang/Codex-Pulse#english\n\n'
        '将应用拖入 Applications。包内已包含 Python 和 Node.js。\n'
        '需另行安装并登录 Codex；键盘联动才需要 G HUB。\n'
        '当前为 ad-hoc 签名，未公证，首次打开说明见：\n'
        'https://github.com/QiushanHuang/Codex-Pulse#中文\n')
    stem = f'Codex-Pulse-v{VERSION}-macos-arm64'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, args.output / f'{stem}.zip')
    run('hdiutil', 'create', '-volname', f'Codex Pulse {VERSION}', '-srcfolder', stage,
        '-format', 'UDZO', args.output / f'{stem}.dmg')
    (args.output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    artifacts = [args.output / f'{stem}.{ext}' for ext in ('dmg', 'zip')] + [args.output / 'release-manifest.json']
    (args.output / 'SHA256SUMS.txt').write_text(''.join(f'{sha256(p)}  {p.name}\n' for p in artifacts))
    print(f'Release artifacts: {args.output}')


if __name__ == '__main__':
    main()
