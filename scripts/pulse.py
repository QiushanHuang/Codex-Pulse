#!/usr/bin/env python3
"""Convenience CLI. Usage: pulse.py status|once|run|lights-on|lights-off|restore."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from codex_pulse.monitor import load
from codex_pulse.configuration import edit_config


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['status','once','run','lights-on','lights-off','restore','preview'])
    parser.add_argument('--scene', choices=['running','completed','reset','low','brightness-test'], default='running')
    parser.add_argument('--tasks', choices=[1,2,3,4], type=int, default=1)
    parser.add_argument('--data-dir', default=str(Path.home()/'Library/Application Support/CodexPulse'))
    args = parser.parse_args()
    directory = Path(args.data_dir).expanduser().resolve()
    if args.command == 'status':
        snapshot = load(directory/'snapshot.json', {'error':'尚未开始采样'})
        print(json.dumps(snapshot, ensure_ascii=False, indent=2))
    elif args.command=='preview':
        import time
        with edit_config(directory) as config:
            if not config.get('lighting'):raise SystemExit('请先开启状态灯光，再演示。')
            seconds=(config.get('lightSettings') or {}).get('cycleSeconds',12)
            seconds=max(2,min(30,seconds)) if isinstance(seconds,(int,float)) else 12
            duration=seconds+2 if args.scene=='running' else 5 if args.scene=='brightness-test' else 8
            config['preview']={'scene':args.scene,'startedAt':time.time(),'taskCount':args.tasks,'duration':duration}
        print(f'演示已启动；约 {duration:g} 秒后返回实时状态，不修改额度或任务记录。')
    elif args.command.startswith('lights-'):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with edit_config(directory) as config:
            config['lighting']=args.command=='lights-on';config.pop('preview',None)
        print('灯光开关已更新；运行中的后台会自动应用。')
    elif args.command == 'restore':
        # Ask the live driver to release first, then recover any crash backup.
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with edit_config(directory) as config:
            config['lighting']=False;config.pop('preview',None)
        import time
        time.sleep(2)
        node = shutil.which('node')
        if not node:
            raise SystemExit('Node.js 22+ 不可用')
        raise SystemExit(subprocess.call([node,str(ROOT/'scripts/keyboard.mjs'),'restore',str(directory)]))
    else:
        command = [sys.executable,'-m','codex_pulse.monitor','--data-dir',str(directory)]
        if args.command=='once':command.append('--once')
        raise SystemExit(subprocess.call(command,cwd=ROOT))


if __name__ == '__main__':main()
