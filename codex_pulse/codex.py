"""Read-only Codex adapters; no model turns, credential copies, or reset redemption."""
from contextlib import closing
from datetime import datetime
import json
import os
from pathlib import Path
import queue
import shutil
import sqlite3
import subprocess
import threading
import time

from .core import task_state


class AppServer:
    ALLOWED = {'initialize', 'account/read', 'account/rateLimits/read'}

    def __init__(self, binary=None):
        candidates = [
            '/Applications/Codex.app/Contents/Resources/codex',
            '/Applications/ChatGPT.app/Contents/Resources/codex',
            str(Path.home() / 'Applications/Codex.app/Contents/Resources/codex'),
            str(Path.home() / 'Applications/ChatGPT.app/Contents/Resources/codex'),
        ]
        self.binary = binary or next((p for p in candidates if Path(p).is_file()), None) or shutil.which('codex')
        if not self.binary:
            raise RuntimeError('找不到 Codex CLI')
        self.process = None
        self.messages = queue.Queue()
        self.next_id = 0

    def start(self):
        self.close()
        self.messages = queue.Queue()
        self.process = subprocess.Popen([self.binary, 'app-server', '--listen', 'stdio://'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True, bufsize=1)
        proc, messages = self.process, self.messages

        def drain():
            try:
                for line in proc.stdout:
                    try:
                        value = json.loads(line)
                        # Do not queue event traffic or unsolicited server requests.
                        if 'id' in value and ('result' in value or 'error' in value):
                            messages.put(value)
                    except ValueError:
                        continue
            finally:
                messages.put({'closed': True})

        threading.Thread(target=drain, daemon=True).start()
        self.call('initialize', {'clientInfo': {'name': 'codex_pulse', 'version': '1.0.0'},
                                 'capabilities': {'experimentalApi': True}})
        self.process.stdin.write('{"method":"initialized"}\n')
        self.process.stdin.flush()

    def call(self, method, params=None, timeout=25):
        if method not in self.ALLOWED:
            raise ValueError('This monitor only supports read methods')
        if self.process is None:
            raise RuntimeError('Codex adapter is not started')
        self.next_id += 1
        request_id = self.next_id
        self.process.stdin.write(json.dumps({'id': request_id, 'method': method, 'params': params or {}}) + '\n')
        self.process.stdin.flush()
        deadline = time.monotonic() + timeout
        while True:
            result = self.messages.get(timeout=max(.01, deadline - time.monotonic()))
            if result.get('closed'):
                raise RuntimeError('Codex App Server 已关闭')
            if result.get('id') != request_id:
                if time.monotonic() >= deadline:
                    raise TimeoutError('Codex 读取超时')
                continue
            if 'error' in result:
                # Surface the failure class, never arbitrary upstream payloads.
                raise RuntimeError(f"Codex 接口错误 {result['error'].get('code', 'unknown')}")
            return result['result']

    def close(self):
        if self.process:
            proc, self.process = self.process, None
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
            for stream in (proc.stdin, proc.stdout):
                if stream:
                    stream.close()


def event_tail(path, max_bytes=512 * 1024):
    """Read only a bounded tail and retain lifecycle fields, not message bodies."""
    events = []
    with open(path, 'rb') as stream:
        size = stream.seek(0, 2)
        stream.seek(max(0, size - max_bytes))
        if size > max_bytes:
            stream.readline()
        lines = stream.read(max_bytes).splitlines()
    for line in lines:
        try:
            record = json.loads(line)
            if record.get('type') != 'event_msg':
                continue
            payload = record.get('payload', {})
            if payload.get('type') not in {'task_started', 'task_complete', 'turn_aborted', 'task_failed',
                                            'item_started', 'item_completed', 'token_count'}:
                continue
            at = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
            events.append({'type': payload['type'], 'turn_id': payload.get('turn_id'), 'at': at})
        except (ValueError, KeyError, TypeError):
            continue
    return events


class LocalTasks:
    def __init__(self, codex_home=None):
        self.root = Path(codex_home or os.environ.get('CODEX_HOME') or Path.home() / '.codex')
        self.cache = {}

    def read(self, limit=30):
        databases = sorted(self.root.glob('state_*.sqlite'), key=lambda p: int(p.stem.split('_')[-1]), reverse=True)
        if not databases:
            raise RuntimeError('本机 Codex 任务数据库不可用')
        with closing(sqlite3.connect(databases[0].as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
            rows = db.execute('SELECT id, coalesce(name,title), rollout_path, updated_at FROM threads '
                              'WHERE archived=0 ORDER BY updated_at DESC LIMIT ?', (limit,)).fetchall()
        tasks = []
        for tid, title, path, updated in rows:
            try:
                p = Path(path).resolve()
                # Restrict metadata pointers to this Codex home's session trees.
                if not any(p.is_relative_to(self.root / d) for d in ('sessions', 'archived_sessions')):
                    continue
                stat = p.stat()
                key = (str(p), stat.st_mtime_ns, stat.st_size)
                if self.cache.get(tid, (None,))[0] != key:
                    self.cache[tid] = (key, event_tail(p))
                state = task_state(self.cache[tid][1], time.time())
            except (OSError, ValueError):
                state = {'status': 'unknown', 'at': updated, 'turnId': None}
            tasks.append({'id': tid, 'title': title or '未命名任务', **state})
        self.cache = {k: v for k, v in self.cache.items() if k in {t['id'] for t in tasks}}
        return sorted(tasks, key=lambda t: (t['status'] != 'active', -t['at']))
