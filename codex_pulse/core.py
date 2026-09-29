"""Pure interpretation of service observations. Percentages are quota, not tokens."""
import math
from datetime import date


def token_integer(value):
    return isinstance(value, int) and not isinstance(value, bool) and 0 <= value < 2**63


def normalize_account_usage(raw):
    """Preserve server day buckets; missing dates are not observations of zero."""
    rows = raw.get('dailyUsageBuckets') if isinstance(raw, dict) else None
    if not isinstance(rows, list):
        return None
    days, seen = [], set()
    for row in rows:
        if not isinstance(row, dict):
            return None
        day, tokens = row.get('startDate'), row.get('tokens')
        try:
            if not isinstance(day, str) or len(day) != 10 or date.fromisoformat(day).isoformat() != day:
                return None
        except ValueError:
            return None
        if day in seen or not token_integer(tokens):
            return None
        seen.add(day)
        days.append({'date': day, 'tokens': tokens})
    summary = raw.get('summary') or {}
    lifetime = summary.get('lifetimeTokens') if isinstance(summary, dict) else None
    return {'days': sorted(days, key=lambda d: d['date']),
            'lifetimeTokens': lifetime if token_integer(lifetime) else None}


def apply_account_usage(snapshot, observation, at):
    if observation.get('accountKey') != snapshot.get('accountKey'):
        return
    if observation.get('usage') is not None:
        snapshot.update(usage=observation['usage'], usageAt=at, usageError=None)
    else:
        snapshot['usageError'] = observation.get('error') or '服务未提供每日用量'


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def normalize_credits(raw):
    """Account credit balance, separate from quota percentages and reset coupons."""
    buckets = raw.get('rateLimitsByLimitId')
    bucket = buckets.get('codex') if isinstance(buckets, dict) else None
    if not isinstance(bucket, dict):
        bucket = raw.get('rateLimits')
    if not isinstance(bucket, dict) or bucket.get('limitId') not in (None, 'codex'):
        return None
    credits = bucket.get('credits')
    if not isinstance(credits, dict):
        return None
    balance = credits.get('balance')
    try:
        balance = float(balance) if not isinstance(balance, bool) else None
    except (ValueError, TypeError, OverflowError):
        balance = None
    return {'balance': balance if number(balance) else None,
            'unlimited': credits.get('unlimited') is True}


def normalize_reset_vouchers(raw):
    inventory = raw.get('rateLimitResetCredits')
    rows = inventory.get('credits') if isinstance(inventory, dict) else None
    if not isinstance(rows, list):
        return None
    result, seen = [], set()
    for row in rows:
        if not isinstance(row, dict) or row.get('status') != 'available':
            continue
        identity = row.get('id')
        if not isinstance(identity, str) or not 0 < len(identity) <= 256 or identity in seen:
            continue
        seen.add(identity)
        value = {'id': identity}
        for field in ('expiresAt', 'grantedAt'):
            at = row.get(field)
            value[field] = at if number(at) and 0 <= at <= 253402300799 else None
        result.append(value)
    return result


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
