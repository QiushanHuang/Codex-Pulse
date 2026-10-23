"""Sampling daemon and local history. Run with python3 -m codex_pulse.monitor."""
import argparse
import copy
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
from .core import normalize, normalize_credits, normalize_reset_vouchers, normalize_account_usage, apply_account_usage, change_kind, burn_rate
from .monitor_lock import acquire_monitor_lock, MonitorAlreadyRunning, MonitorParentExited
from .attention import overlay
from .file_wake import FileWake
from .remote_notifications import RemoteNotifications, read_json, status as remote_status


def quota_interval(tasks):
    return 15 if any(t.get('status') == 'active' or t.get('isRunning') for t in tasks) else 120


def merge_quota_push(previous, update):
    merged = copy.deepcopy(previous)
    buckets = merged.setdefault('rateLimitsByLimitId', {})
    updates = dict(update.get('rateLimitsByLimitId') or {})
    legacy = update.get('rateLimits')
    if isinstance(legacy, dict):
        updates.setdefault(legacy.get('limitId') or 'codex', legacy)
    for key, bucket in updates.items():
        if isinstance(bucket, dict):
            buckets[key] = {**buckets.get(key, {}), **bucket}
    if legacy is not None:
        merged['rateLimits'] = legacy
    if 'rateLimitResetCredits' in update:
        merged['rateLimitResetCredits'] = update['rateLimitResetCredits']
    return merged


def task_events(previous, tasks, now):
    startup = previous is None
    previous = previous or {}
    events = []
    for task in tasks:
        old = previous.get(task['id'])
        identity = (task['status'], task.get('turnId'), task.get('attentionId'))
        prior = (old['status'], old.get('turnId'), old.get('attentionId')) if old else None
        waiting = task['status'] in ('waiting_approval', 'waiting_input')
        if startup and not waiting:
            continue
        if identity != prior and task['status'] in {'completed', 'failed', 'interrupted', 'waiting_approval', 'waiting_input'} and 0 <= now-task['at'] < (86400 if waiting else 120):
            key = hashlib.sha256(repr((task['id'], identity, task['at'])).encode()).hexdigest()
            events.append({'id': key, 'kind': task['status'], 'at': now if waiting else task['at'], 'message': task['title'],
                           'taskId': task['id'], 'turnId': task.get('turnId')})
    return events


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
                'credits': normalize_credits(raw),
                'resetVouchers': normalize_reset_vouchers(raw),
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
    stop, inbox, wake = threading.Event(), queue.Queue(), threading.Event()
    refresh_quota = threading.Event()
    def stopped(*_):
        stop.set()
        wake.set()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, stopped)
    server = AppServer(args.codex)
    def notification(value):
        if value['method'] == 'account/rateLimits/updated':
            inbox.put(('quota_push', value['params'], time.time()))
        else:
            inbox.put(('account_changed', None, time.time()))
            refresh_quota.set()
        wake.set()
    server.on_notification = notification
    history = History(directory / 'history.sqlite')
    try:
        remote = RemoteNotifications(directory)
        remote.start_worker(stop)
    except Exception:
        remote = None
        remote_status(directory, 'failed', '通知队列暂不可用，额度监控继续运行。', time.time())
    task_reader = LocalTasks()
    snapshot = {'version': 1, 'generatedAt': time.time(), 'quotaAt': 0, 'windows': [], 'tasks': [],
                'events': [], 'quotaError': '正在读取额度', 'taskError': None, 'resetCredits': None, 'credits': None,
                'usage': None, 'usageAt': 0, 'usageError': '正在读取每日用量',
                'taskScope': '本机最近 30 个会话 · 完成表示轮次结束', 'keyboard': {'status': 'off', 'message': '灯光关闭'}}
    old_snapshot = load(directory / 'snapshot.json', {})
    # Keep last known values visibly stale while reconnecting; do not manufacture an empty/full quota.
    for key in ('windows', 'quotaAt', 'resetCredits', 'resetVouchers', 'credits', 'events', 'accountKey', 'usage', 'usageAt'):
        if key in old_snapshot:
            snapshot[key] = old_snapshot[key]

    def sample_quota():
        usage_account, next_usage = None, 0
        failures = 0
        while not stop.is_set():
            refresh_quota.clear()
            try:
                if server.process is None or server.process.poll() is not None:
                    server.start()
                account = server.call('account/read', {'refreshToken': False}).get('account') or {}
                raw = server.call('account/rateLimits/read')
                raw['accountId'] = raw.get('accountId') or account.get('email') or f'unidentified-{os.getpid()}'
                inbox.put(('quota', raw, time.time()))
                wake.set()
                failures = 0
                account_key = hashlib.sha256(str(raw['accountId']).encode()).hexdigest()
                if usage_account != account_key or time.monotonic() >= next_usage:
                    # Optional analytics failure must not fail a successful quota read.
                    observation = {'accountKey': account_key}
                    try:
                        observation['usage'] = normalize_account_usage(server.call('account/usage/read'))
                    except Exception as error:
                        observation['error'] = f'每日用量暂不可用 · {type(error).__name__}'
                    inbox.put(('usage', observation, time.time()))
                    usage_account, next_usage = account_key, time.monotonic() + 300
                    wake.set()
            except Exception as error:
                inbox.put(('error', f'额度暂不可用 · {type(error).__name__}', time.time()))
                server.close()
                failures += 1
                wake.set()
            if args.once:
                return
            # Account analytics stay at five minutes, including activity-triggered quota reads.
            delay = min(300, 60 * 2**min(failures-1, 3)) if failures else quota_interval(snapshot['tasks'])
            refresh_quota.wait(delay)

    sampler = threading.Thread(target=sample_quota, daemon=True)
    sampler.start()
    keyboard = None
    if not args.once:
        node = args.node or shutil.which('node')
        if node:
            keyboard = subprocess.Popen([node, str(Path(__file__).resolve().parent.parent / 'scripts' / 'keyboard.mjs'),
                                         'run', str(directory)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    previous_tasks = None
    watcher = FileWake(wake)
    next_quota_trigger = 0
    last_quota = None
    refresh_requested = time.time()
    quota_seen = False
    deadline = time.monotonic()+65
    try:
        while not stop.is_set():
            wake.clear()
            approval_deadlines = []
            if args.parent and os.getppid() != args.parent:
                break
            request = load(directory / 'quota-refresh-request.json', {})
            requested_at = request.get('at', 0) if isinstance(request, dict) else 0
            if isinstance(requested_at, (int, float)) and requested_at > refresh_requested:
                refresh_requested = requested_at
                refresh_quota.set()
            try:
                tasks = overlay(directory, task_reader.read(), time.time(), approval_deadlines)
                watcher.set_paths(task_reader.watched_paths | {directory / 'task-attention.json', directory / 'quota-refresh-request.json'})
                events = task_events(previous_tasks, tasks, time.time())
                snapshot['events'].extend(events)
                activity_changed = previous_tasks is not None and any(
                    t['id'] not in previous_tasks or
                    (t['status'], t.get('turnId')) != (previous_tasks[t['id']]['status'], previous_tasks[t['id']].get('turnId'))
                    for t in tasks)
                if activity_changed and time.monotonic() >= next_quota_trigger:
                    refresh_quota.set()
                    next_quota_trigger = time.monotonic() + 5
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
                got_quota = kind in ('quota', 'error') or got_quota
                quota_seen = quota_seen or got_quota
                if kind == 'quota':
                    last_quota = value
                    result = history.observe(value, at)
                    if snapshot.get('accountKey') not in (None, result['accountKey']):
                        snapshot['events'] = []
                        snapshot.update(usage=None, usageAt=0, usageError='正在读取当前账号用量')
                    snapshot.update({k: v for k, v in result.items() if k != 'newEvents'})
                    snapshot['events'].extend(result['newEvents'])
                    snapshot['quotaAt'] = at
                    snapshot['quotaError'] = None if snapshot['windows'] else '服务未提供额度窗口'
                    preferences = read_json(config_path).get('quotaNotificationSettings', {})
                    if remote is not None and isinstance(preferences, dict):
                        receipt = read_json(directory / f"quota-reset-{snapshot['accountKey']}.json")
                        try:
                            remote.observe(snapshot, preferences, time.time(), receipt)
                        except Exception:
                            # Optional remote delivery must not invalidate a successful quota read.
                            remote_status(directory, 'failed', '无法记录重置通知，请重新启动监控。', at)
                elif kind == 'usage':
                    apply_account_usage(snapshot, value, at)
                elif kind == 'quota_push':
                    if last_quota:
                        last_quota = merge_quota_push(last_quota, value)
                        result = history.observe(last_quota, at)
                        snapshot.update({k: v for k, v in result.items() if k != 'newEvents'})
                        snapshot['events'].extend(result['newEvents'])
                    # Only full reads establish freshness for all windows.
                elif kind == 'account_changed':
                    last_quota = None
                    if remote is not None:
                        remote.invalidate()
                    snapshot.update(quotaError='账号状态变化，正在重新读取', usage=None, usageAt=0,
                                    usageError='正在读取当前账号用量')
                else:
                    snapshot['quotaError'] = value
                    if remote is not None:
                        remote.invalidate()
            now = time.time()
            snapshot['generatedAt'] = now
            snapshot['refreshPolicy'] = {'quotaSeconds': quota_interval(snapshot['tasks']),
                                         'tasks': 'filesystem' if watcher.queue else 'polling'}
            snapshot['events'] = [e for e in snapshot['events'] if now-e['at'] < 86400][-20:]
            snapshot['keyboard'] = load(directory / 'keyboard.json', {'status': 'off', 'message': '灯光未启动'})
            if keyboard and keyboard.poll() is not None:
                snapshot['keyboard'] = {'status': 'error', 'message': '灯光进程已退出；请重新启动监控'}
            atomic(directory / 'snapshot.json', snapshot)
            if args.once and ((quota_seen and not sampler.is_alive()) or time.monotonic()>deadline):
                print(json.dumps(snapshot, ensure_ascii=False))
                if snapshot['quotaError']:
                    raise SystemExit(1)
                break
            if args.once:
                stop.wait(1)
            else:
                # At most one rescan per second during token streaming; idle wakeups are sparse.
                stop.wait(1)
                wait_seconds = 14 if watcher.queue else 4
                if approval_deadlines:
                    wait_seconds = min(wait_seconds, max(0, min(approval_deadlines)-time.time()))
                wake.wait(wait_seconds)
    finally:
        stop.set()
        refresh_quota.set()
        watcher.close()
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
