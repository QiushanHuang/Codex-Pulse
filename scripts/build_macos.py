#!/usr/bin/env python3
"""Build a local SwiftUI app and WidgetKit extension without third-party packages."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time
try:
    from .input_continuity import read_signature, write_json, build_report
except ImportError:
    from input_continuity import read_signature, write_json, build_report

ROOT = Path(__file__).resolve().parent.parent


def select_python(candidates=None):
    """Select a working interpreter, not the Xcode-dependent /usr/bin shim."""
    if candidates is None:
        candidates = ['/opt/homebrew/bin/python3', '/usr/local/bin/python3',
                      '/Library/Developer/CommandLineTools/usr/bin/python3', sys.executable]
    for candidate in dict.fromkeys(candidates):
        if candidate == '/usr/bin/python3':
            continue
        try:
            result = subprocess.run([candidate, '-c',
                'import sys, sqlite3, ssl; assert sys.version_info >= (3, 9)'],
                capture_output=True, timeout=10)
            if result.returncode == 0:
                return candidate
        except (OSError, subprocess.TimeoutExpired):
            pass
    raise RuntimeError('找不到可运行的 Python 3.9+；请安装 Python 后重新构建')


def plist(file, data):
    file.parent.mkdir(parents=True, exist_ok=True)
    with file.open('wb') as stream:
        plistlib.dump(data, stream)


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--identity', default='-', help='Optional existing Apple signing identity; default: local ad hoc')
    parser.add_argument('--register', action='store_true', help='Register the built app and its widget locally')
    parser.add_argument('--reuse-widget', action='store_true', help='Reuse an existing built widget when only the app changes')
    parser.add_argument('--sdk', help='Optional installed macOS SDK path for the app compiler')
    parser.add_argument('--install', action='store_true', help='Back up and replace /Applications/Codex Pulse.app, then verify runtime input status')
    args = parser.parse_args()
    installed = Path('/Applications/Codex Pulse.app')
    previous = read_signature(installed)
    python = select_python()
    app = ROOT / 'build/Codex Pulse.app'
    extension = app / 'Contents/PlugIns/CodexPulseWidget.appex'
    for bundle in (app, extension):
        (bundle / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    iconset = ROOT / 'build/CodexPulse.iconset'
    iconset.mkdir(parents=True, exist_ok=True)
    baseline = resources / 'input-install-baseline.json'
    write_json(baseline, {'signature': previous, 'source': 'previous_install', 'at': time.time()} if previous else {})
    source_icon = ROOT / 'assets/branding/codex-pulse-logo-v3.png'
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            suffix = '@2x' if scale == 2 else ''
            run('sips', '-z', size * scale, size * scale, source_icon,
                '--out', iconset / f'icon_{size}x{size}{suffix}.png')
    run('iconutil', '-c', 'icns', iconset, '-o', resources / 'CodexPulse-v3.icns')
    for directory in ('codex_pulse', 'scripts'):
        shutil.copytree(ROOT / directory, resources / 'backend' / directory, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    run(shutil.which('node') or '/usr/local/bin/node', ROOT/'scripts/build_ambient_catalog.mjs', resources/'ambient-catalog.json')
    common = {'CFBundleDevelopmentRegion':'en', 'CFBundleVersion':'11', 'CFBundleShortVersionString':'2.1.2',
              'LSMinimumSystemVersion':'14.0'}
    plist(app / 'Contents/Info.plist', {**common, 'CFBundleIdentifier':'local.qiushan.CodexPulse',
          'CFBundleName':'Codex Pulse', 'CFBundleDisplayName':'Codex Pulse', 'CFBundleExecutable':'CodexPulse',
          'CFBundlePackageType':'APPL', 'NSHighResolutionCapable':True,
          'CFBundleIconFile':'CodexPulse-v3.icns', 'LSUIElement':True,
          'PulsePython':python, 'PulseNode':shutil.which('node') or '/usr/local/bin/node',
          'CFBundleURLTypes':[{'CFBundleURLName':'CodexPulse','CFBundleURLSchemes':['codexpulse']}]})
    # A real extension target supplies the NSExtensionMain entry point required by macOS.
    if args.reuse_widget:
        run('codesign', '--verify', '--strict', extension)
    else:
        run(python, ROOT/'scripts/generate_xcode_project.py')
        with (ROOT/'build/widget-build.log').open('w') as log:
            subprocess.run(['xcodebuild','-project',str(ROOT/'macos/CodexPulse.xcodeproj'),'-target','CodexPulseWidget',
                            '-configuration','Release','CONFIGURATION_BUILD_DIR='+str(ROOT/'build/xcode'),
                            'CODE_SIGN_IDENTITY='+args.identity],stdout=log,stderr=subprocess.STDOUT,check=True)
        shutil.copytree(ROOT/'build/xcode/CodexPulseWidget.appex',extension,dirs_exist_ok=True)
    sdk = args.sdk or subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'], text=True).strip()
    target = subprocess.check_output(['uname','-m'],text=True).strip()+'-apple-macosx14.0'
    common_flags = ['xcrun','swiftc','-parse-as-library','-O','-sdk',sdk,'-target',target,
                    '-framework','SwiftUI','-framework','WidgetKit',str(ROOT/'macos/Shared.swift')]
    run(*common_flags, '-framework','AppKit','-framework','Network','-framework','JavaScriptCore','-framework','Security',ROOT/'macos/ApplicationLifecycle.swift',ROOT/'macos/RuntimePaths.swift',ROOT/'macos/InputAuthorization.swift',ROOT/'macos/AmbientDesignPreview.swift',ROOT/'macos/InputMonitorState.swift',ROOT/'macos/AmbientCatalog.swift',ROOT/'macos/AmbientLighting.swift',ROOT/'macos/AmbientLibrary.swift', ROOT/'macos/MenuBar.swift', ROOT/'macos/LightingDiagram.swift', ROOT/'macos/WindowPresentation.swift', ROOT/'macos/StickyPresentation.swift', ROOT/'macos/StickyWindowSupport.swift', ROOT/'macos/StickyDashboard.swift', ROOT/'macos/PresetPagination.swift', ROOT/'macos/PulseConfiguration.swift', ROOT/'macos/WorkbenchState.swift', ROOT/'macos/WorkbenchViews.swift', ROOT/'macos/App.swift', '-o', app/'Contents/MacOS/CodexPulse')
    run('codesign','--force','--sign',args.identity, app)
    run('codesign','--verify','--deep','--strict',app)
    report = build_report(app, installed, previous)
    write_json(ROOT/'build/input-build-report.json', report)
    print('签名连续性：'+report['continuity']+'；ListenEvent 授权须由安装后 app 实测。')
    if args.install:
        run(python, ROOT/'scripts/install_macos.py', '--app', app)
    if args.register:
        if args.install:
            app = installed
            extension = app / 'Contents/PlugIns/CodexPulseWidget.appex'
        run('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-f',app)
        run('pluginkit','-a',extension)
    print(app)


if __name__ == '__main__':
    main()
