#!/usr/bin/env python3
"""Optional login startup. No installation is performed by the build script."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess

ROOT=Path(__file__).resolve().parent.parent
LABEL='local.qiushan.CodexPulse.login'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['enable','disable','status'])
    args=parser.parse_args()
    file=Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
    domain=f'gui/{os.getuid()}'
    if args.action=='status':
        print('已配置登录启动' if file.exists() else '未配置登录启动');return
    if args.action=='disable':
        subprocess.run(['launchctl','bootout',f'{domain}/{LABEL}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        if file.exists():file.unlink()
        print('已关闭此工具的登录启动；额度历史保留。');return
    app=ROOT/'build/Codex Pulse.app'
    if not app.exists():raise SystemExit('请先运行 build_macos.py')
    file.parent.mkdir(parents=True,exist_ok=True)
    with file.open('wb') as stream:
        plistlib.dump({'Label':LABEL,'ProgramArguments':['/usr/bin/open',str(app)],'RunAtLoad':True},stream)
    subprocess.run(['launchctl','bootout',f'{domain}/{LABEL}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    subprocess.run(['launchctl','bootstrap',domain,str(file)],check=True)
    print('已配置登录启动。请保留应用所在目录。')


if __name__=='__main__':main()
