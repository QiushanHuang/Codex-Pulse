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

from .core import task_state, compact_task_events
from .attention import QUESTION


class AppServer:
    ALLOWED = {'initialize', 'account/read', 'account/rateLimits/read', 'account/usage/read'}

    def __init__(self, binary=None):
        self.explicit_binary = binary
        self.binary = binary or self.discover_binary()
        self.process = None
        self.messages = queue.Queue()
        self.notifications = queue.Queue(maxsize=32)
        self.on_notification = None
        self.next_id = 0

    def accept_notification(self, value):
        if 'id' in value or value.get('method') not in {'account/rateLimits/updated', 'account/updated'}:
            return False
        if not isinstance(value.get('params'), dict):
            return False
        if self.on_notification:
            self.on_notification(value)
        else:
            if self.notifications.full():
                self.notifications.get_nowait()
            self.notifications.put_nowait(value)
        return True

    @staticmethod
    def discover_binary():
        candidates = [
            str(root / f'{app}.app' / 'Contents/Resources' / relative)
            for root in (Path('/Applications'), Path.home() / 'Applications')
            for app in ('Codex', 'ChatGPT')
            for relative in ('codex-cli/CodexCLI.app/Contents/MacOS/codex', 'codex')
        ]
        binary = next((p for p in candidates if Path(p).is_file()), None) or shutil.which('codex')
        if not binary:
            raise RuntimeError('找不到 Codex CLI')
        return binary

    def start(self):
        self.close()
        # App updates can move the bundled CLI while Pulse remains running.
        self.binary = self.explicit_binary or self.discover_binary()
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
                        # Only read-only account notifications; never answer server requests.
                        if 'id' in value and ('result' in value or 'error' in value):
                            messages.put(value)
                        else:
                            self.accept_notification(value)
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
    return event_chunk(path, max_bytes=max_bytes)[0]


def event_chunk(path, offset=0, max_bytes=512 * 1024):
    events = []
    with open(path, 'rb') as stream:
        size = stream.seek(0, 2)
        start = max(offset, size - max_bytes, 0)
        stream.seek(start)
        if start > offset:
            stream.readline()
        start = stream.tell()
        data = stream.read(max_bytes)
        # A writer can be halfway through a line; retry that line on the next append.
        end = data.rfind(b'\n') + 1
        if end < len(data):
            try:
                # JSONL permits a complete final record without a trailing newline.
                if isinstance(json.loads(data[end:]), dict):
                    end = len(data)
            except (ValueError, UnicodeError):
                pass
        lines = data[:end].splitlines()
        next_offset = start + end
    for line in lines:
        try:
            record = json.loads(line)
            payload = record.get('payload', {})
            record_type, kind = record.get('type'), payload.get('type')
            if record_type == 'response_item':
                at = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
                if kind in ('function_call', 'custom_tool_call') and isinstance(payload.get('name'), str) and QUESTION.search(payload['name']) and isinstance(payload.get('call_id'), str):
                    events.append({'type': 'question_requested', 'call_id': payload['call_id'],
                                   'async': payload['name'].endswith('request_user_input_async'), 'at': at})
                elif kind in ('function_call_output', 'custom_tool_call_output') and isinstance(payload.get('call_id'), str):
                    events.append({'type': 'question_returned', 'call_id': payload['call_id'], 'at': at})
                elif kind == 'message' and payload.get('role') == 'user':
                    events.append({'type': 'question_reply', 'at': at})
                continue
            if record_type == 'turn_context':
                at = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
                event = {'type': 'turn_context', 'turn_id': payload.get('turn_id'), 'at': at}
                if payload.get('approvals_reviewer') in ('user', 'auto_review'):
                    event['approval_reviewer'] = payload['approvals_reviewer']
                events.append(event)
                continue
            if record_type != 'event_msg':
                continue
            if kind == 'user_message':
                at = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
                events.append({'type': 'question_reply', 'at': at})
                continue
            if payload.get('type') not in {'task_started', 'task_complete', 'turn_aborted', 'task_failed',
                                            'item_started', 'item_completed', 'token_count'}:
                continue
            at = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00')).timestamp()
            event = {'type': payload['type'], 'turn_id': payload.get('turn_id'), 'at': at}
            if payload['type'] == 'token_count':
                info = payload.get('info') or {}
                usage = info.get('total_token_usage') if isinstance(info, dict) else None
                if isinstance(usage, dict):
                    for source, target in (('total_tokens', 'tokensUsed'), ('input_tokens', 'inputTokens'),
                                           ('output_tokens', 'outputTokens'), ('cached_input_tokens', 'cachedInputTokens')):
                        value = usage.get(source)
                        if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 2**63-1:
                            event[target] = value
            events.append(event)
        except (ValueError, KeyError, TypeError):
            continue
    return events, next_offset


class LocalTasks:
    def __init__(self, codex_home=None):
        self.root = Path(codex_home or os.environ.get('CODEX_HOME') or Path.home() / '.codex').resolve()
        self.cache = {}
        self.offsets = {}
        self.reviewers = {}
        self.watched_paths = set()
        self.usage_observations = []

    def indexed_reviewer(self, tid, path, stat, turn_id, now):
        """Read a turn's small context once, even when it is outside the session tail."""
        if not turn_id:
            return None
        key = (str(path), stat.st_ino, turn_id)
        cached = self.reviewers.get(tid)
        if cached and cached[0] == key and (cached[1] is not None or now-cached[2] < 30):
            return cached[1]
        reviewer = None
        try:
            databases = sorted(self.root.glob('thread_history_*.sqlite'),
                               key=lambda p: int(p.stem.split('_')[-1]), reverse=True)
            if databases:
                with closing(sqlite3.connect(databases[0].as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
                    row = db.execute('SELECT rollout_byte_offset FROM thread_turns WHERE thread_id=? AND turn_id=?',
                                     (tid, turn_id)).fetchone()
                if row and isinstance(row[0], int) and 0 <= row[0] < stat.st_size:
                    with path.open('rb') as stream:
                        stream.seek(row[0])
                        # Do not reuse the tail reader here: this is a bounded read at the indexed start.
                        data = stream.read(64 * 1024)
                    for line in data.splitlines():
                        try:
                            record = json.loads(line)
                            payload = record.get('payload', {})
                            if record.get('type') == 'turn_context' and payload.get('turn_id') == turn_id:
                                value = payload.get('approvals_reviewer')
                                reviewer = value if value in ('user', 'auto_review') else None
                        except (ValueError, UnicodeError, TypeError, AttributeError):
                            continue
        except (OSError, ValueError, sqlite3.Error):
            pass
        self.reviewers[tid] = (key, reviewer, now)
        return reviewer

    def take_usage_observations(self):
        observations, self.usage_observations = self.usage_observations, []
        return observations

    def read(self, limit=30):
        if limit <= 0:
            return []
        databases = sorted(self.root.glob('state_*.sqlite'), key=lambda p: int(p.stem.split('_')[-1]), reverse=True)
        if not databases:
            raise RuntimeError('本机 Codex 任务数据库不可用')
        self.watched_paths = {databases[0], Path(str(databases[0]) + '-wal')}
        with closing(sqlite3.connect(databases[0].as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
            columns = {row[1] for row in db.execute('PRAGMA table_info(threads)')}
            token_column = 'tokens_used' if 'tokens_used' in columns else 'NULL'
            def field(name):
                return name if name in columns else 'NULL'
            conditions = ['archived=0', "trim(coalesce(name,title,''))<>''"]
            if 'thread_source' in columns:
                conditions.append("coalesce(thread_source,'')<>'guardian_review'")
            if 'model' in columns:
                conditions.append("coalesce(model,'')<>'codex-auto-review'")
            cursor = db.execute(f'SELECT id, coalesce(name,title), rollout_path, updated_at, {token_column}, '
                                f'{field("source")} FROM threads WHERE '+ ' AND '.join(conditions) +
                                ' ORDER BY updated_at DESC')
            rows = []
            for row in cursor:
                # Older databases may only store the structured subagent marker.
                try:
                    source = json.loads(row[5]) if isinstance(row[5], str) else row[5]
                    if isinstance(source, dict) and (source.get('subagent') or {}).get('other') == 'guardian':
                        continue
                except (ValueError, TypeError, AttributeError):
                    pass
                rows.append(row[:5])
                if len(rows) >= limit:
                    break
        tasks = []
        for tid, title, path, updated, tokens in rows:
            usage = {'tokensUsed': tokens if isinstance(tokens, int) and 0 <= tokens <= 2**63-1 else None}
            try:
                p = Path(path).resolve()
                # Restrict metadata pointers to this Codex home's session trees.
                if not any(p.is_relative_to(self.root / d) for d in ('sessions', 'archived_sessions')):
                    continue
                stat = p.stat()
                self.watched_paths.add(p)
                key = (str(p), stat.st_mtime_ns, stat.st_size, stat.st_ino)
                if self.cache.get(tid, (None,))[0] != key:
                    old_key, old_events = self.cache.get(tid, (None, []))
                    append = old_key and old_key[0] == key[0] and old_key[3] == key[3] and old_key[2] < key[2]
                    # Startup can encounter a question older than the original 512 KiB tail.
                    # Pay this bounded scan once; streaming updates still read only appended bytes.
                    events, offset = event_chunk(p, self.offsets.get(tid, 0) if append else 0,
                                                 max_bytes=512*1024 if append else 2*1024*1024)
                    self.usage_observations.extend({'taskId':tid,'at':e['at'],'tokensUsed':e['tokensUsed']}
                                                   for e in events if 'tokensUsed' in e)
                    self.offsets[tid] = offset
                    combined = (old_events if append else []) + events
                    self.cache[tid] = (key, compact_task_events(combined))
                now = time.time()
                state = task_state(self.cache[tid][1], now)
                if 'approvalReviewer' not in state:
                    reviewer = self.indexed_reviewer(tid, p, stat, state.get('turnId'), now)
                    if reviewer:
                        state['approvalReviewer'] = reviewer
                # Each event is a cumulative observation, never an increment.
                for event in reversed(self.cache[tid][1]):
                    if 'tokensUsed' in event:
                        usage = {k: event[k] for k in ('tokensUsed', 'inputTokens', 'outputTokens', 'cachedInputTokens') if k in event}
                        break
            except (OSError, ValueError):
                state = {'status': 'unknown', 'at': updated, 'turnId': None}
            tasks.append({'id': tid, 'title': title or '未命名任务', **state, **usage})
        self.cache = {k: v for k, v in self.cache.items() if k in {t['id'] for t in tasks}}
        self.offsets = {k: v for k, v in self.offsets.items() if k in self.cache}
        self.reviewers = {k: v for k, v in self.reviewers.items() if k in self.cache}
        return sorted(tasks, key=lambda t: (t['status'] != 'active', -t['at']))
