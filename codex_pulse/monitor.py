"""Sampling daemon and local history. Run with python3 -m codex_pulse.monitor."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import sqlite3
import subprocess
import threading
import time

from .codex import AppServer, LocalTasks
from .core import normalize, change_kind, burn_rate
from .monitor_lock import acquire_monitor_lock, MonitorAlreadyRunning, MonitorParentExited


class History:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.execute('CREATE TABLE IF NOT EXISTS samples (account TEXT, window TEXT, at REAL, used REAL, reset REAL, data TEXT)')
        self.db.execute('CREATE INDEX IF NOT EXISTS lookup ON samples(account, window, at)')

    def observe(self, raw, now):
        account = hashlib.sha256(str(raw.get('accountId') or 'unknown').encode()).hexdigest()
        windows, events = normalize(raw), []
        for window in windows:
            row = self.db.execute('SELECT data FROM samples WHERE account=? AND window=? ORDER BY at DESC LIMIT 1',
                                  (account, window['id'])).fetchone()
            if row:
                old = json.loads(row[0])
                kind = change_kind(old, window, now)
                if kind:
                    events.append({'kind': kind, 'at': now, 'message': f"{window['name']} {window['label']} " +
                                   ('额度已重置' if kind == 'reset' else '额度回升（重置或服务端调整）')})
            self.db.execute('INSERT INTO samples VALUES(?,?,?,?,?,?)',
                            (account, window['id'], now, window['used'], window['reset'], json.dumps(window)))
            points = [{'at': a, 'used': u, 'reset': r} for a, u, r in self.db.execute(
                'SELECT at,used,reset FROM samples WHERE account=? AND window=? AND at>=? ORDER BY at',
                (account, window['id'], now-3600))]
            rate = burn_rate(points)
            window['burnRate'] = rate
            window['hoursLeft'] = round(window['remaining']/rate, 1) if rate and rate > 0 else None
            window['history'] = [{'at': p['at'], 'remaining': 100-p['used']} for p in points]
        self.db.execute('DELETE FROM samples WHERE at < ?', (now - 30*86400,))
        self.db.commit()
        return {'windows': windows, 'newEvents': events, 'accountKey': account,
                'resetCredits': (raw.get('rateLimitResetCredits') or {}).get('availableCount')}

    def close(self):
        self.db.close()


def atomic(path, value):
    temporary = path.with_name(path.name + f'.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False))
    temporary.chmod(0o600)
    temporary.replace(path)


def load(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def run(args):
    os.umask(0o077)
    directory = Path(args.data_dir).expanduser().resolve()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    try:
        lock = acquire_monitor_lock(directory / 'monitor.lock', parent=args.parent)
    except MonitorParentExited:
        return
    except MonitorAlreadyRunning as error:
        print(str(error), flush=True)
        raise SystemExit(75)
    config_path = directory / 'config.json'
    if not config_path.exists():
        atomic(config_path, {'lighting': False})
    stop, inbox = threading.Event(), queue.Queue()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    server = AppServer(args.codex)
    history = History(directory / 'history.sqlite')
    task_reader = LocalTasks()
    snapshot = {'version': 1, 'generatedAt': time.time(), 'quotaAt': 0, 'windows': [], 'tasks': [],
                'events': [], 'quotaError': '正在读取额度', 'taskError': None, 'resetCredits': None,
                'taskScope': '本机最近 30 个会话 · 完成表示轮次结束', 'keyboard': {'status': 'off', 'message': '灯光关闭'}}
    old_snapshot = load(directory / 'snapshot.json', {})
    # Keep last known values visibly stale while reconnecting; do not manufacture an empty/full quota.
    for key in ('windows', 'quotaAt', 'resetCredits', 'events', 'accountKey'):
        if key in old_snapshot:
            snapshot[key] = old_snapshot[key]

    def sample_quota():
        while not stop.is_set():
            try:
                if server.process is None or server.process.poll() is not None:
                    server.start()
                account = server.call('account/read', {'refreshToken': False}).get('account') or {}
                raw = server.call('account/rateLimits/read')
                raw['accountId'] = raw.get('accountId') or account.get('email') or f'unidentified-{os.getpid()}'
                inbox.put(('quota', raw, time.time()))
            except Exception as error:
                inbox.put(('error', f'额度暂不可用 · {type(error).__name__}', time.time()))
                server.close()
            if args.once:
                return
            stop.wait(60)

    sampler = threading.Thread(target=sample_quota, daemon=True)
    sampler.start()
    keyboard = None
    if not args.once:
        node = args.node or shutil.which('node')
        if node:
            keyboard = subprocess.Popen([node, str(Path(__file__).resolve().parent.parent / 'scripts' / 'keyboard.mjs'),
                                         'run', str(directory)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    previous_tasks = None
    deadline = time.monotonic()+65
    try:
        while not stop.is_set():
            if args.parent and os.getppid() != args.parent:
                break
            try:
                tasks = task_reader.read()
                if previous_tasks is not None:
                    for task in tasks:
                        old = previous_tasks.get(task['id'])
                        if old and task['status'] in {'completed', 'failed', 'interrupted'} and \
                           (old['status'], old['turnId']) != (task['status'], task['turnId']) and \
                           time.time()-task['at'] < 120:
                            snapshot['events'].append({'kind': task['status'], 'at': task['at'], 'message': task['title']})
                previous_tasks = {t['id']: t for t in tasks}
                snapshot['tasks'] = tasks
                snapshot['taskError'] = None
            except Exception as error:
                snapshot['taskError'] = f'任务状态暂不可用 · {type(error).__name__}'
                snapshot['tasks'] = []
            got_quota = False
            while True:
                try:
                    kind, value, at = inbox.get_nowait()
                except queue.Empty:
                    break
                got_quota = True
                if kind == 'quota':
                    result = history.observe(value, at)
                    if snapshot.get('accountKey') not in (None, result['accountKey']):
                        snapshot['events'] = []
                    snapshot.update({k: v for k, v in result.items() if k != 'newEvents'})
                    snapshot['events'].extend(result['newEvents'])
                    snapshot['quotaAt'] = at
                    snapshot['quotaError'] = None if snapshot['windows'] else '服务未提供额度窗口'
                else:
                    snapshot['quotaError'] = value
            now = time.time()
            snapshot['generatedAt'] = now
            snapshot['events'] = [e for e in snapshot['events'] if now-e['at'] < 86400][-20:]
            snapshot['keyboard'] = load(directory / 'keyboard.json', {'status': 'off', 'message': '灯光未启动'})
            if keyboard and keyboard.poll() is not None:
                snapshot['keyboard'] = {'status': 'error', 'message': '灯光进程已退出；请重新启动监控'}
            atomic(directory / 'snapshot.json', snapshot)
            if args.once and (got_quota or time.monotonic()>deadline):
                print(json.dumps(snapshot, ensure_ascii=False))
                if snapshot['quotaError']:
                    raise SystemExit(1)
                break
            stop.wait(1 if args.once else 5)
    finally:
        stop.set()
        if keyboard and keyboard.poll() is None:
            keyboard.terminate()
            try:
                keyboard.wait(timeout=12)
            except subprocess.TimeoutExpired:
                keyboard.kill();keyboard.wait()
        server.close()
        sampler.join(timeout=2)
        history.close()
        lock.close()


def main():
    parser = argparse.ArgumentParser(description='Codex Pulse 本机额度与任务监控')
    parser.add_argument('--data-dir', default=str(Path.home() / 'Library/Application Support/CodexPulse'))
    parser.add_argument('--codex')
    parser.add_argument('--node')
    parser.add_argument('--parent', type=int)
    parser.add_argument('--once', action='store_true')
    run(parser.parse_args())


if __name__ == '__main__':
    main()
