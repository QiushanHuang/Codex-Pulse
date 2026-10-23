"""Optional lifecycle signal bridge. Never returns a Codex policy decision."""
import argparse
from contextlib import contextmanager
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import sys
import time
import uuid

MARKER = 'Codex Pulse · task signals'
QUESTION = re.compile(r'(^|[._])request_user_input(_async)?$')
PERMISSION = re.compile(r'(^|[._])request_permissions$')
APPROVAL_GRACE_SECONDS = 3


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open('a') as handle:
        path.chmod(0o600)
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def read(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write(path, value):
    temp = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    try:
        temp.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False))
        temp.chmod(0o600)
        temp.replace(path)
    finally:
        temp.unlink(missing_ok=True)


def fingerprint(payload):
    # Opaque correlation key; command text and question content never leave stdin.
    tool, tool_input = payload.get('tool_name'), payload.get('tool_input')
    if tool in ('Bash', 'apply_patch') and isinstance(tool_input, dict) and isinstance(tool_input.get('command'), str):
        # PermissionRequest adds a description that PostToolUse need not include.
        # Both hooks expose the same canonical command for these tools.
        tool_input = {'command': tool_input['command']}
    value = [tool, tool_input]
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def record(directory, payload, now=None):
    now = time.time() if now is None else now
    tid = payload.get('session_id')
    try:
        tid = str(uuid.UUID(tid))
    except (ValueError, TypeError, AttributeError):
        return
    event, tool = payload.get('hook_event_name'), payload.get('tool_name', '')
    if not isinstance(tool, str):
        return
    path = directory / 'task-attention.json'
    with locked(directory / 'task-attention.lock'):
        state = read(path)
        pending = [r for r in state.get('pending', []) if isinstance(r, dict)
                   and isinstance(r.get('at'), (int, float)) and 0 <= now-r['at'] < 86400]
        key = fingerprint(payload)
        if event == 'PermissionRequest' or (event == 'PreToolUse' and (QUESTION.search(tool) or PERMISSION.search(tool))):
            pending = [r for r in pending if not (r.get('taskId') == tid and r.get('key') == key)]
            pending.append({'taskId': tid, 'turnId': payload.get('turn_id'), 'at': now,
                            'id': uuid.uuid4().hex, 'key': key,
                            'callId': payload.get('tool_use_id'),
                            'async': tool.endswith('request_user_input_async'),
                            'status': 'waiting_input' if QUESTION.search(tool) else 'waiting_approval'})
        elif event == 'PostToolUse':
            pending = [r for r in pending if not (r.get('taskId') == tid and not r.get('async')
                       and (r.get('key') == key or (r.get('callId') and r['callId'] == payload.get('tool_use_id'))))]
        elif event in ('UserPromptSubmit', 'Interrupt', 'SessionEnd'):
            pending = [r for r in pending if r.get('taskId') != tid]
        else:
            return
        write(path, {'version': 1, 'at': now, 'pending': pending[-100:]})
        sentinel = directory / 'attention-pending'
        if pending:
            sentinel.touch(mode=0o600)
        else:
            sentinel.unlink(missing_ok=True)


def overlay(directory, tasks, now, approval_deadlines=None):
    signals = read(directory / 'task-attention.json').get('pending', [])
    output = []
    for task in tasks:
        candidates = [r for r in signals if isinstance(r, dict) and r.get('taskId') == task['id']
                      and isinstance(r.get('at'), (int, float)) and 0 <= now-r['at'] < 86400
                      and r.get('status') in ('waiting_input', 'waiting_approval')
                      and task.get('lastUserInputAt', 0) <= r['at']
                      and r.get('turnId') == task.get('turnId')
                      and (r.get('async') or task['status'] not in ('completed', 'failed', 'interrupted')
                           or task['at'] < r['at'])]
        if approval_deadlines is not None and task.get('approvalReviewer') == 'user':
            approval_deadlines.extend(r['at'] + APPROVAL_GRACE_SECONDS for r in candidates
                                      if r['status'] == 'waiting_approval' and now-r['at'] < APPROVAL_GRACE_SECONDS)
        candidates = [r for r in candidates if r['status'] != 'waiting_approval' or
                      (task.get('approvalReviewer') == 'user' and now-r['at'] >= APPROVAL_GRACE_SECONDS)]
        if candidates:
            signal = max(candidates, key=lambda r: (r['status'] == 'waiting_approval', r['at']))
            output.append({**task, 'status': signal['status'], 'at': signal['at'],
                           'attentionId': signal.get('callId') or signal['id'], 'attentionSource': 'hook',
                           'isRunning': bool(signal.get('async') and (task['status'] == 'active' or task.get('isRunning')))})
        else:
            # A previously overlaid task supplied by a caller must regain its base state.
            output.append({**task, 'status': 'active'} if task['status'].startswith('waiting_') and task.get('attentionSource') != 'session' else task)
    return output


def merge_hooks(existing, python, script, data_dir):
    merged = copy.deepcopy(existing)
    hooks = merged.setdefault('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError('Invalid existing hooks configuration')
    invoke = ' '.join(map(shlex.quote, [python, '-B', script, '--hook', '--data-dir', str(data_dir)]))
    guarded = f'if [ -f {shlex.quote(str(Path(data_dir) / "attention-pending"))} ]; then {invoke}; fi'
    for event, matcher, command in (
        ('PermissionRequest', '*', invoke),
        ('PreToolUse', r'(^|[._])request_user_input(_async)?$|(^|[._])request_permissions$', invoke),
        ('PostToolUse', '*', guarded),
        ('UserPromptSubmit', '*', guarded),
        ('Interrupt', '*', guarded),
        ('SessionEnd', '*', guarded),
    ):
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise ValueError('Invalid existing hook groups')
        # Remove only our handlers, preserving other handlers in mixed groups.
        kept = []
        for group in groups:
            group = copy.deepcopy(group)
            group['hooks'] = [h for h in group.get('hooks', []) if h.get('statusMessage') != MARKER]
            if group['hooks']:
                kept.append(group)
        kept.append({'matcher': matcher, 'hooks': [{'type': 'command', 'command': command,
                     'timeout': 2, 'statusMessage': MARKER}]})
        hooks[event] = kept
    return merged


def configure(home, directory, python, script):
    path = home / 'hooks.json'
    with locked(home / 'pulse-hooks.lock'):
        if path.is_symlink():
            raise ValueError('请先手动检查 hooks.json 符号链接')
        existing = json.loads(path.read_text()) if path.exists() else {}
        if not isinstance(existing, dict):
            raise ValueError('现有 hooks.json 格式不受支持')
        merged = merge_hooks(existing, python, script, directory)
        backup = None
        if existing != merged:
            if path.exists():
                backup = home / ('hooks-before-pulse-' + uuid.uuid4().hex + '.json')
                write(backup, existing)
            write(path, merged)
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        receipt = {'configured': True, 'at': time.time(), 'path': str(path),
                   'backup': str(backup) if backup else None, 'trustRequired': True}
        write(directory / 'attention-hook-status.json', receipt)
        return receipt


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-dir', default=str(Path.home() / 'Library/Application Support/CodexPulse'))
    parser.add_argument('--hook', action='store_true')
    parser.add_argument('--configure', action='store_true')
    parser.add_argument('--confirmed', action='store_true')
    parser.add_argument('--codex-home', default=str(Path.home() / '.codex'))
    args = parser.parse_args()
    os.umask(0o077)
    directory = Path(args.data_dir).expanduser()
    if args.hook:
        # Informational, fast and fail-open; never break an agent turn.
        try:
            payload = json.loads(sys.stdin.buffer.read(1024 * 1024))
            if isinstance(payload, dict):
                record(directory, payload)
        except Exception:
            pass
    elif args.configure and args.confirmed:
        print(json.dumps(configure(Path(args.codex_home).expanduser(), directory, sys.executable,
                                   str(Path(__file__).resolve().parent.parent / 'scripts/task_signal_hook.py'))))
    else:
        parser.error('Configuration requires --configure --confirmed')


if __name__ == '__main__':
    main()
