#!/usr/bin/env python3
"""Run isolated native checks without starting the monitor or controlling devices."""
import os
import sys
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/swift-tests'
SUITES = {
    'ApplicationLifecycle': ['ApplicationLifecycle'],
    'RuntimePaths': ['RuntimePaths'],
    'AmbientCatalog': ['AmbientCatalog'],
    'AmbientJavaScript': [],
    'Configuration': ['PulseConfiguration'],
    'Diagram': ['Shared', 'LightingDiagram'],
    'InputMonitorState': ['InputMonitorState'],
    'InputSignature': ['InputAuthorization', 'InputMonitorState'],
    'MenuBar': ['MenuBar'],
    'PresetPagination': ['PresetPagination'],
    'StickyPresentation': ['Shared', 'StickyPresentation'],
    'StickyWindow': ['StickyWindowSupport', 'PulseConfiguration'],
    'Trend': ['Shared'],
    'WindowPresentation': ['WindowPresentation'],
    'WorkbenchState': ['Shared', 'WorkbenchState'],
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    sdk = os.environ.get('PULSE_MACOS_SDK') or subprocess.check_output(
        ['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    catalog = OUT / 'ambient-catalog.json'
    subprocess.run(['node', str(ROOT / 'scripts/build_ambient_catalog.mjs'), str(catalog)], check=True)
    selected = sys.argv[1:] or list(SUITES)
    for name in selected:
        sources = SUITES[name]
        executable = OUT / name
        command = ['xcrun', 'swiftc', '-parse-as-library', '-O', '-sdk', sdk]
        for framework in ('SwiftUI', 'AppKit', 'WidgetKit', 'JavaScriptCore', 'Security', 'Network'):
            command += ['-framework', framework]
        command += [str(ROOT / 'macos' / f'{source}.swift') for source in sources]
        command += [str(ROOT / 'tests' / f'{name}Tests.swift'), '-o', str(executable)]
        subprocess.run(command, check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(executable)], check=True)
        arguments = {'AmbientCatalog': [str(catalog)],
                     'AmbientJavaScript': [str(ROOT / 'scripts/ambient-engine.mjs')],
                     'MenuBar': [str(OUT / 'menu-icons')],
                     'Trend': [str(OUT)]}.get(name, [])
        print(f'Running {name}', flush=True)
        subprocess.run([str(executable), *arguments], check=True)
    print(f'PASS: {len(selected)} native suites')


if __name__ == '__main__':
    main()
