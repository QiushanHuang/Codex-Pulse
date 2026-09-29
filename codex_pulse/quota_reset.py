"""Explicit, confirmed reset redemption. Never used by the sampling daemon."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import time
from uuid import UUID

from .codex import AppServer
from .monitor import atomic, load


class ResetAppServer(AppServer):
    ALLOWED = AppServer.ALLOWED | {'account/rateLimitResetCredit/consume'}


MESSAGES = {
    'reset': '重置成功，已使用 1 次重置机会；正在刷新额度。',
    'alreadyRedeemed': '这次操作此前已成功完成，没有重复使用重置次数。',
    'nothingToReset': '服务确认当前没有可重置的额度窗口，未执行重置。',
    'noCredit': '当前账号没有可用重置次数。',
}


def execute_reset(server, directory, request_id, account_key, *, confirmed=False):
    def result(state, message, outcome=None):
        return {'requestID': request_id, 'accountKey': account_key, 'state': state,
                'outcome': outcome, 'message': message, 'at': time.time()}
    try:
        valid_id = str(UUID(request_id)) == request_id
    except (ValueError, TypeError, AttributeError):
        valid_id = False
    if not confirmed or not valid_id or not isinstance(account_key, str) or not re.fullmatch('[0-9a-f]{64}', account_key):
        return result('rejected', '缺少有效确认、请求编号或账号绑定，未执行重置。')
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    latest_path = directory / f'quota-reset-{account_key}.json'
    receipts = directory / 'reset-receipts'
    receipts.mkdir(exist_ok=True, mode=0o700)
    receipt_path = receipts / f'{request_id}.json'
    with (directory / 'quota-reset.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return result('blocked', '另一个重置操作仍在处理，请等待其结果。')
        previous = load(receipt_path, {})
        latest = load(latest_path, {})
        if previous and previous.get('accountKey') != account_key:
            return result('rejected', '请求编号所属账号不一致，未执行重置。')
        if latest.get('state') in ('pending', 'unknown') and latest.get('requestID') != request_id:
            return result('blocked', '上一次操作结果尚未确认，请重试同一次操作，不能发起新的重置。')
        submitted = False
        def save(value):
            # Save account guard first so a crash cannot authorize a second key.
            atomic(latest_path, value)
            atomic(receipt_path, value)
            return value
        try:
            server.start()
            account = server.call('account/read', {'refreshToken': False}).get('account') or {}
            raw = server.call('account/rateLimits/read')
            identity = raw.get('accountId') or account.get('email')
            if not isinstance(identity, str) or not identity or account.get('type') == 'apiKey' or hashlib.sha256(identity.encode()).hexdigest() != account_key:
                return result('rejected', '登录账号已变化或无法确认，请刷新后重新确认。未执行重置。')
            current = server.call('account/read', {'refreshToken': False}).get('account') or {}
            if current.get('type') != account.get('type') or current.get('email') != account.get('email'):
                return result('rejected', '验证期间登录账号发生变化，未执行重置。')
            if previous.get('state') == 'completed':
                return previous
            retry = previous.get('state') in ('pending', 'unknown') or (latest.get('requestID') == request_id and latest.get('state') in ('pending', 'unknown'))
            if latest.get('requestID') == request_id and latest.get('state') == 'completed':
                return latest
            count = (raw.get('rateLimitResetCredits') or {}).get('availableCount')
            if not retry and (not isinstance(count, int) or isinstance(count, bool) or count <= 0):
                if count == 0:
                    return save(result('completed', MESSAGES['noCredit'], 'noCredit'))
                return result('rejected', '服务未提供可用重置次数，未执行重置。')
            save(result('pending', '重置请求已提交，正在等待服务确认。'))
            submitted = True
            response = server.call('account/rateLimitResetCredit/consume', {'idempotencyKey': request_id})
            outcome = response.get('outcome') if isinstance(response, dict) else None
            if outcome not in MESSAGES:
                return save(result('unknown', '服务返回了未知结果；请重试同一次操作确认，勿重复发起。'))
            return save(result('completed', MESSAGES[outcome], outcome))
        except Exception:
            if submitted:
                return save(result('unknown', '连接中断，重置可能已执行。重试将沿用同一请求编号，避免重复使用次数。'))
            return result('rejected', '无法验证当前账号或重置次数，未发送重置请求。')
        finally:
            server.close()
            atomic(directory / 'quota-refresh-request.json', {'at': time.time()})


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', required=True)
    parser.add_argument('--request-id', required=True)
    parser.add_argument('--expected-account-key', required=True)
    parser.add_argument('--confirmed', action='store_true')
    args = parser.parse_args()
    value = execute_reset(ResetAppServer(), Path(args.data_dir), args.request_id,
                          args.expected_account_key, confirmed=args.confirmed)
    print(json.dumps(value, ensure_ascii=False, allow_nan=False))


if __name__ == '__main__':
    main()
