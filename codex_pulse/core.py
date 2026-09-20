"""Pure interpretation of service observations. Percentages are quota, not tokens."""
import math


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def normalize(raw):
    buckets = raw.get('rateLimitsByLimitId')
    if not isinstance(buckets, dict) or not buckets:
        legacy = raw.get('rateLimits')
        buckets = {legacy.get('limitId') or 'codex': legacy} if isinstance(legacy, dict) else {}
    result = []
    for bucket_id, bucket in buckets.items():
        if not isinstance(bucket, dict):
            continue
        for slot in ('primary', 'secondary'):
            window = bucket.get(slot)
            if not isinstance(window, dict):
                continue
            used, duration, reset = (window.get(k) for k in ('usedPercent', 'windowDurationMins', 'resetsAt'))
            if not number(used) or not number(duration) or duration <= 0:
                continue
            used = min(100, max(0, used))
            label = {300: '5 小时', 10080: '每周', 1440: '每日'}.get(duration, f'{duration:g} 分钟')
            result.append({'id': f'{bucket_id}:{duration:g}', 'bucket': bucket_id,
                           'name': bucket.get('limitName') or ('Codex' if bucket_id == 'codex' else bucket_id),
                           'label': label, 'duration': duration, 'used': used, 'remaining': 100 - used,
                           'reset': reset if number(reset) else None})
    return sorted(result, key=lambda w: (w['bucket'] != 'codex', w['bucket'], w['duration']))


def change_kind(old, new, now):
    if old['id'] != new['id']:
        return None
    a, b = old.get('reset'), new.get('reset')
    if number(a) and number(b) and b > a + 60 and now >= a:
        return 'reset'
    if new['used'] < old['used']:
        return 'recovery'
    return None


def burn_rate(points):
    if len(points) < 2:
        return None
    # Keep only the most recent continuous, monotonic segment of this window.
    segment = [points[-1]]
    for p in reversed(points[:-1]):
        nxt = segment[0]
        same_deadline = (p['reset'] == nxt['reset'] or
                         number(p['reset']) and number(nxt['reset']) and abs(p['reset']-nxt['reset']) <= 60)
        if not same_deadline or p['used'] > nxt['used'] or not 0 < nxt['at'] - p['at'] <= 600:
            break
        if points[-1]['at'] - p['at'] > 3600:
            break
        segment.insert(0, p)
    elapsed = segment[-1]['at'] - segment[0]['at']
    if elapsed < 300:
        return None
    return round((segment[-1]['used'] - segment[0]['used']) * 3600 / elapsed, 2)


def task_state(events, now):
    result = {'status': 'unknown', 'at': 0, 'turnId': None}
    terminal = {'task_complete': 'completed', 'turn_aborted': 'interrupted', 'task_failed': 'failed'}
    for event in events:
        kind = event.get('type')
        if kind not in {*terminal, 'task_started', 'item_started', 'item_completed', 'token_count'}:
            continue
        if kind in terminal:
            result = {'status': terminal[kind], 'at': event['at'], 'turnId': event.get('turn_id')}
        elif kind == 'task_started' or result['status'] not in terminal.values():
            result = {'status': 'active', 'at': event['at'], 'turnId': event.get('turn_id') or result['turnId']}
        elif event.get('turn_id') and event['turn_id'] != result['turnId']:
            result = {'status': 'active', 'at': event['at'], 'turnId': event['turn_id']}
    if result['status'] == 'active' and now - result['at'] > 1800:
        result['status'] = 'unknown'
    return result
