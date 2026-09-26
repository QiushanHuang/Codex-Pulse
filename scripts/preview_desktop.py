#!/usr/bin/env python3
"""Build/run native desktop checks and synthetic previews; never launches a backend."""
import argparse
import json
import os
import platform
from pathlib import Path
import plistlib
import subprocess
import uuid
from build_macos import APP_SOURCES, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interactive', action='store_true')
    parser.add_argument('--build-only', action='store_true', help='Compile without launching checks or the interactive preview')
    args = parser.parse_args()
    out = ROOT / 'build/desktop-preview'
    out.mkdir(parents=True, exist_ok=True)
    # Compile the actual app model and views with a synthetic-data entry point.
    app_source = out / 'AppLibrary.swift'
    app_source.write_text((ROOT / 'macos/App.swift').read_text().replace('@main\nstruct CodexPulseApp', 'struct CodexPulseApp'))
    bundle = out / 'Codex Pulse Preview.app'
    executable = bundle / 'Contents/MacOS/DesktopPreview'
    executable.parent.mkdir(parents=True, exist_ok=True)
    sdk = os.environ.get('PULSE_MACOS_SDK') or subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
    command = ['xcrun', 'swiftc', '-parse-as-library', '-sdk', sdk]
    for framework in ['SwiftUI', 'AppKit', 'WidgetKit', 'JavaScriptCore', 'Security', 'Network']:
        command += ['-framework', framework]
    sources = [ROOT / 'macos/Shared.swift'] + [app_source if name == 'App' else ROOT / 'macos' / f'{name}.swift' for name in APP_SOURCES]
    subprocess.run(command + list(map(str, sources)) + [str(ROOT / 'tests/DesktopSurfaceChecks.swift'), '-o', str(executable)], check=True)
    with (bundle / 'Contents/Info.plist').open('wb') as stream:
        plistlib.dump({'CFBundleIdentifier': 'local.qiushan.CodexPulse.DesktopPreview', 'CFBundleName': 'Codex Pulse Preview', 'CFBundleExecutable': 'DesktopPreview', 'CFBundlePackageType': 'APPL', 'NSHighResolutionCapable': True}, stream)
    subprocess.run(['codesign', '--force', '--sign', '-', str(bundle)], check=True)
    if args.build_only:
        print(bundle)
    elif args.interactive:
        subprocess.Popen([str(executable), '--interactive'], stdout=subprocess.DEVNULL, stderr=(out / 'interactive.log').open('w'))
        print(bundle)
    else:
        subprocess.run([str(executable), str(out / 'images')], check=True)
        if int(platform.mac_ver()[0].split('.')[0]) < 15:
            print('Cold-launch scene check requires macOS 15+; native surface checks completed.')
            return
        # Use the same Launch Services open-application event as the installed app.
        # A bare executable launch need not present a singleton SwiftUI Window.
        report = out / f'startup-check-{uuid.uuid4().hex}.json'
        subprocess.run(['/usr/bin/open', '-n', '-W', str(bundle), '--args', '--startup-check', '--startup-report', str(report)], check=True, timeout=20)
        state = json.loads(report.read_text())
        assert state == {'sidebarEnabled': True, 'handleVisible': True}, state
        print('PASS: cold SwiftUI launch with saved enabled sidebar', flush=True)


if __name__ == '__main__':
    main()
