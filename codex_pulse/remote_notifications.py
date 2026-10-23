"""Opt-in reset alerts, durable deduplication and bounded remote delivery.

Only fresh full quota reads establish resets. No quota-changing RPCs are used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import smtplib
import sqlite3
import ssl
import subprocess
import threading
import time
from email.message import EmailMessage
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

from .core import change_kind, number


EVIDENCE_SECONDS = 600


def voucher_inventory(snapshot):
    """A partial/unknown inventory cannot prove voucher consumption."""
    count, rows = snapshot.get('resetCredits'), snapshot.get('resetVouchers')
    if type(count) is not int or count < 0 or not isinstance(rows, list) or len(rows) != count:
        return None
    values = {}
    for row in rows:
        if not isinstance(row, dict):
            return None
        identity = row.get('id')
        if not isinstance(identity, str) or not identity or identity in values:
            return None
        expiry = row.get('expiresAt')
        values[identity] = expiry if number(expiry) else None
    return values


def external_evidence(old, snapshot, now):
    """Correlate independent service observations; the source app is unknown.

    Available IDs must disappear before their known expiry with an equal count
    decrease. Pair with a Codex quota recovery within ten minutes in either order.
    """
    previous = {w['id']: w for w in old.get('windows', [])}
    prior = old.get('externalEvidence') or {}
    recovery = [r for r in prior.get('recovery', []) if 0 <= now-r['at'] <= EVIDENCE_SECONDS]
    consumption = prior.get('consumption')
    if consumption and not 0 <= now-consumption['at'] <= EVIDENCE_SECONDS:
        consumption = None
    consumed_now = False
    if 0 <= now-old.get('observedAt', 0) <= EVIDENCE_SECONDS:
        before, after = old.get('resetInventory'), voucher_inventory(snapshot)
        if isinstance(before, dict) and after is not None and len(after) < len(before):
            removed = sorted(set(before)-set(after))
            if len(removed) == len(before)-len(after) and all(number(before[i]) and before[i] > now for i in removed):
                consumed_now = True
                consumption = dict(ids=removed, at=now)
        for window in snapshot['windows']:
            prior_window = previous.get(window['id'])
            if (window.get('bucket') == 'codex' and prior_window
                    and number(prior_window.get('reset')) and now < prior_window['reset']
                    and window['used'] < prior_window['used']):
                recovery = [r for r in recovery if r['id'] != window['id']]
                recovery.append(dict(id=window['id'], at=now))
    return dict(consumption=consumption, recovery=recovery), consumed_now


def read_json(path, default=None):
    try:
        value = json.loads(Path(path).read_text())
        return value if isinstance(value, dict) else (default or {})
    except (OSError, ValueError):
        return default or {}


def status(directory, state, message, now):
    path = directory / 'remote-notification-status.json'
    temporary = path.with_name(path.name + f'.{os.getpid()}.{threading.get_ident()}.tmp')
    temporary.write_text(json.dumps(dict(state=state, message=message, at=now), ensure_ascii=False))
    temporary.chmod(0o600)
    temporary.replace(path)


def settings_key(settings):
    return hashlib.sha256(json.dumps(settings, sort_keys=True).encode()).hexdigest()


def credentials():
    result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s',
                             'com.qiushan.codexpulse.remote-notifications', '-a', 'quota', '-w'],
                            capture_output=True, timeout=10)
    if result.returncode:
        raise ValueError('请先在设置中保存推送地址或邮箱授权码')
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise ValueError('通知凭据格式无效')
    return value


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('推送服务发生重定向，请直接填写最终 HTTPS 地址')


def deliver_remote(settings, title, body, event_id):
    secret = credentials()
    if settings.get('channel', 'push') == 'push':
        url = secret.get('pushURL', '').strip()
        parsed = urlsplit(url)
        if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or not parsed.path.strip('/') or parsed.query or parsed.fragment:
            raise ValueError('请填写完整 HTTPS Bark 推送地址（含设备密钥）')
        data = json.dumps(dict(title=title, body=body, group='Codex Pulse')).encode()
        request = Request(url, data=data, headers={'Content-Type': 'application/json'}, method='POST')
        with build_opener(NoRedirect()).open(request, timeout=15) as response:
            value = json.loads(response.read(65536))
            if value.get('code') != 200:
                raise ValueError('推送服务未确认发送成功')
    elif settings.get('channel') == 'email':
        host = settings.get('smtpHost', '').strip()
        sender, recipient = (settings.get(k, '').strip() for k in ('sender', 'recipient'))
        user = settings.get('smtpUser', '').strip() or sender
        password = secret.get('smtpPassword', '')
        if not host or not sender or not recipient or not password or any(c in sender+recipient for c in '\r\n'):
            raise ValueError('请完整填写 SMTP、发件邮箱、收件邮箱及授权码')
        port = int(settings.get('smtpPort') or 465)
        message = EmailMessage()
        message['Subject'], message['From'], message['To'] = title, sender, recipient
        message['Message-ID'] = f'<{hashlib.sha256(event_id.encode()).hexdigest()}@codexpulse.local>'
        message.set_content(body)
        context = ssl.create_default_context()
        if settings.get('smtpTLS', 'ssl') == 'starttls':
            with smtplib.SMTP(host, port, timeout=15) as client:
                client.ehlo(); client.starttls(context=context); client.ehlo()
                client.login(user, password)
                if client.send_message(message):
                    raise ValueError('邮件服务器拒绝收件地址')
        else:
            with smtplib.SMTP_SSL(host, port, timeout=15, context=context) as client:
                client.login(user, password)
                if client.send_message(message):
                    raise ValueError('邮件服务器拒绝收件地址')
    else:
        raise ValueError('请选择推送或邮件')


class RemoteNotifications:
    def __init__(self, directory, deliver=deliver_remote):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / 'remote-notifications.sqlite'
        self.deliver = deliver
        self.verified_at = None
        with self.db() as db:
            db.execute('CREATE TABLE IF NOT EXISTS baseline (id INTEGER PRIMARY KEY, data TEXT)')
            db.execute('CREATE TABLE IF NOT EXISTS alerts (id TEXT PRIMARY KEY, settings TEXT, body TEXT, created REAL, due REAL, attempts INTEGER, state TEXT)')
        self.path.chmod(0o600)

    def db(self):
        # Connections belong to a single call/thread and are always closed.
        from contextlib import contextmanager
        @contextmanager
        def connection():
            db = sqlite3.connect(self.path, timeout=5)
            try:
                with db:
                    yield db
            finally:
                db.close()
        return connection()

    def observe(self, snapshot, settings, now, receipt=None):
        at = snapshot.get('quotaAt', 0)
        if snapshot.get('quotaError') or not snapshot.get('accountKey') or not snapshot.get('windows') or not 0 <= now-at <= 180:
            return
        key, account = settings_key(settings), snapshot['accountKey']
        with self.db() as db:
            row = db.execute('SELECT data FROM baseline WHERE id=1').fetchone()
            old = json.loads(row[0]) if row else {}
            continuous = old.get('key') == key and old.get('account') == account and settings.get('enabled') is True
            if not continuous:
                db.execute("UPDATE alerts SET state='cancelled' WHERE state IN ('pending','sending')")
            previous = {w['id']: w for w in old.get('windows', [])}
            manual_id = old.get('manualID') if old.get('account') == account else None
            confirmed_manual = bool(receipt and receipt.get('accountKey') == account
                                    and receipt.get('state') == 'completed'
                                    and receipt.get('outcome') in ('reset', 'alreadyRedeemed')
                                    and receipt.get('requestID')
                                    and receipt.get('requestID') != manual_id
                                    and 0 <= now-receipt.get('at', 0) <= 86400)
            awaiting_manual = bool(receipt and receipt.get('accountKey') == account
                                   and receipt.get('state') in ('pending', 'unknown')
                                   and 0 <= now-receipt.get('at', 0) <= 600)
            external, consumed_now = external_evidence(old, snapshot, now) if continuous else ({}, False)
            local_pending = old.get('localPendingInventory') if continuous else None
            if local_pending and not 0 <= now-local_pending['at'] <= EVIDENCE_SECONDS:
                local_pending = None
            # Local receipts may precede the inventory update. Attribute its first
            # subsequent voucher loss to that known operation, rather than Tibo.
            if confirmed_manual:
                local_pending = None if consumed_now else dict(at=now, requestID=receipt['requestID'])
            consumed_locally = bool(local_pending and consumed_now)
            if consumed_locally:
                local_pending = None
            if confirmed_manual or awaiting_manual or consumed_locally:
                external = {}
            external_event = None
            if continuous and settings.get('manual', True) and external.get('consumption') and external.get('recovery'):
                consumption = external['consumption']
                identities = json.dumps(consumption['ids'], separators=(',', ':'))
                external_event = 'external:'+account+':'+hashlib.sha256(identities.encode()).hexdigest()
                recovered = {r['id'] for r in external['recovery']}
                summary = ' · '.join(f"{w['label']}剩余 {w['remaining']:.0f}%" for w in snapshot['windows'] if w['id'] in recovered)
                self.enqueue(db, external_event, key, '检测到外部手动重置：未到期重置券减少，服务额度已恢复。'+summary+'。', now)
                external = {}
            # One successful voucher can also advance a window deadline. Prefer its receipt.
            if continuous and not confirmed_manual and not awaiting_manual and not external_event:
                for window in snapshot['windows']:
                    selected = {300: 'fiveHour', 10080: 'weekly'}.get(window['duration'])
                    if selected and settings.get(selected, True) and window['id'] in previous and change_kind(previous[window['id']], window, now) == 'reset':
                        event = f"natural:{account}:{window['id']}:{window['reset']}"
                        self.enqueue(db, event, key, f"{window['name']} {window['label']}额度已自然重置，剩余 {window['remaining']:.0f}%。", now)
            if receipt and receipt.get('accountKey') == account and receipt.get('state') == 'completed' and receipt.get('outcome') in ('reset', 'alreadyRedeemed'):
                request_id = receipt.get('requestID')
                if request_id and request_id != manual_id:
                    if continuous and settings.get('manual', True) and 0 <= now-receipt.get('at', 0) <= 86400:
                        self.enqueue(db, f'manual:{account}:{request_id}', key, '服务已确认使用重置券后的额度重置成功。请打开 Pulse 查看最新额度。', now)
                    manual_id = request_id
            # Preserve the prior deadline while a voucher RPC is unresolved. A failed/no-op
            # reply can still expose a genuine natural reset on the next successful read.
            baseline_windows = old['windows'] if continuous and awaiting_manual else snapshot['windows']
            inventory = old.get('resetInventory') if continuous and awaiting_manual else voucher_inventory(snapshot)
            value = dict(account=account, key=key, windows=baseline_windows, manualID=manual_id,
                         resetInventory=inventory, externalEvidence=external,
                         localPendingInventory=local_pending, observedAt=now)
            db.execute('INSERT OR REPLACE INTO baseline VALUES(1,?)', (json.dumps(value),))
            db.execute("DELETE FROM alerts WHERE created<?", (now-30*86400,))
        self.verified_at = now

    def ready(self, now):
        return self.verified_at is not None and 0 <= now-self.verified_at <= 180

    def invalidate(self):
        self.verified_at = None

    @staticmethod
    def enqueue(db, event, key, body, now):
        db.execute('INSERT OR IGNORE INTO alerts VALUES(?,?,?,?,?,0,?)',
                   (event, key, body, now, now, 'pending'))

    def dispatch(self, settings, now):
        key = settings_key(settings)
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute("UPDATE alerts SET state='cancelled' WHERE settings!=? AND state IN ('pending','sending')", (key,))
            if settings.get('enabled') is not True:
                db.execute("UPDATE alerts SET state='cancelled' WHERE state IN ('pending','sending')")
                return
            db.execute("UPDATE alerts SET state='failed' WHERE created<? AND state IN ('pending','sending')", (now-86400,))
            # Crash recovery: an interrupted request may have been delivered remotely.
            db.execute("UPDATE alerts SET state='pending' WHERE state='sending' AND due<=? AND attempts<3", (now,))
            db.execute("UPDATE alerts SET state='failed' WHERE state='sending' AND due<=? AND attempts>=3", (now,))
            row = db.execute("SELECT id,body,attempts FROM alerts WHERE state='pending' AND due<=? ORDER BY created LIMIT 1", (now,)).fetchone()
            if not row:
                return
            event, body, attempts = row
            db.execute("UPDATE alerts SET state='sending',attempts=?,due=? WHERE id=?", (attempts+1, now+120, event))
        try:
            self.deliver(settings, 'Codex 额度已重置', body, event)
        except Exception as error:
            state = 'failed' if attempts >= 2 else 'pending'
            message = '发送失败：请检查通知设置、钥匙串权限或网络。' + ('已停止重试。' if state == 'failed' else '稍后自动重试。')
            # Exceptions can contain SMTP credentials or push URLs. Never persist their text.
            message += f'（{type(error).__name__}）'
            with self.db() as db:
                db.execute('UPDATE alerts SET state=?,due=? WHERE id=?', (state, now+60*(attempts+1), event))
            status(self.directory, state, message, now)
        else:
            with self.db() as db:
                db.execute("UPDATE alerts SET state='sent' WHERE id=?", (event,))
            status(self.directory, 'sent', '通知服务已接受发送，请在手机上确认收到。', now)

    def start_worker(self, stop):
        def work():
            while not stop.wait(5):
                try:
                    settings = read_json(self.directory/'config.json').get('quotaNotificationSettings', {})
                    if isinstance(settings, dict) and self.ready(time.time()):
                        self.dispatch(settings, time.time())
                except Exception:
                    status(self.directory, 'failed', '通知队列暂不可用，请重新启动监控。', time.time())
        thread = threading.Thread(target=work, daemon=True, name='quota-notifications')
        thread.start()
        return thread


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-dir', required=True)
    parser.add_argument('--test', action='store_true', required=True)
    args = parser.parse_args()
    directory = Path(args.data_dir)
    settings = read_json(directory/'config.json').get('quotaNotificationSettings', {})
    try:
        deliver_remote(settings, 'Codex Pulse 测试通知', '额度重置通知连接测试。收到此消息表示手机通知通道可用。', f'test:{time.time_ns()}')
        message, ok = '测试已提交给通知服务，请在手机上确认收到。', True
    except Exception as error:
        message, ok = f'测试发送失败，请检查设置、钥匙串权限或网络。（{type(error).__name__}）', False
    print(json.dumps(dict(ok=ok, message=message), ensure_ascii=False))
    raise SystemExit(0 if ok else 1)


if __name__ == '__main__':
    main()
