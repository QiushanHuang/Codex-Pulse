import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from codex_pulse import core
from test_core import usage


class RemoteNotificationTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        self.assertIsNotNone(importlib.util.find_spec('codex_pulse.remote_notifications'),
                             '额度重置手机通知模块尚未实现')
        from codex_pulse.remote_notifications import RemoteNotifications
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sent = []
        self.root = Path(self.temp.name)
        self.engine = RemoteNotifications(self.root, deliver=lambda *args: self.sent.append(args))
        self.settings = dict(enabled=True, channel='push', fiveHour=True, weekly=True, manual=True)

    def sample(self, reset=1000, used=90, account='A', at=900):
        return dict(accountKey=account, windows=core.normalize(usage(used, reset)),
                    quotaAt=at, quotaError=None)

    def test_confirmed_natural_reset_only_once_across_restart(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 3, at=1100), self.settings, 1100)
        self.engine.dispatch(self.settings, 1100)
        from codex_pulse.remote_notifications import RemoteNotifications
        restarted = RemoteNotifications(self.root, deliver=lambda *a: self.sent.append(a))
        restarted.observe(self.sample(2000, 4, at=1120), self.settings, 1120)
        restarted.dispatch(self.settings, 1120)
        self.assertEqual(len(self.sent), 1)
        self.assertIn('每周', self.sent[0][2])

    def test_clock_alone_recovery_errors_and_account_switch_do_not_notify(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(1000, 0, at=1100), self.settings, 1100)
        bad = self.sample(2000, at=1110); bad['quotaError'] = 'offline'
        self.engine.observe(bad, self.settings, 1110)
        self.engine.observe(self.sample(3000, account='B', at=1120), self.settings, 1120)
        self.engine.dispatch(self.settings, 1120)
        self.assertEqual(self.sent, [])

    def test_manual_requires_successful_current_account_receipt(self):
        self.engine.observe(self.sample(), self.settings, 900)
        receipt = dict(requestID='r1', accountKey='A', state='unknown', outcome='reset', at=950)
        self.engine.observe(self.sample(at=951), self.settings, 951, receipt)
        self.engine.dispatch(self.settings, 951)
        self.assertEqual(self.sent, [])
        receipt['state'] = 'completed'
        self.engine.observe(self.sample(at=952), self.settings, 952, receipt)
        self.engine.dispatch(self.settings, 952)
        self.engine.observe(self.sample(at=953), self.settings, 953, receipt)
        self.engine.dispatch(self.settings, 953)
        self.assertEqual(len(self.sent), 1)
        self.assertIn('重置券', self.sent[0][2])

    def test_disabled_scope_and_enable_do_not_replay_old_resets(self):
        self.settings['weekly'] = False
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100)
        self.engine.dispatch(self.settings, 1100)
        self.settings['enabled'] = False
        self.engine.observe(self.sample(3000, 0, at=2100), self.settings, 2100)
        self.settings.update(enabled=True, weekly=True)
        self.engine.observe(self.sample(3000, 0, at=2110), self.settings, 2110)
        self.engine.dispatch(self.settings, 2110)
        self.assertEqual(self.sent, [])

    def test_failed_delivery_retries_then_persists_success(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100)
        def fail(*args): raise OSError('secret must never be logged')
        self.engine.deliver = fail
        self.engine.dispatch(self.settings, 1100)
        self.engine.deliver = lambda *a: self.sent.append(a)
        self.engine.dispatch(self.settings, 1101)
        self.assertEqual(self.sent, [])
        self.engine.dispatch(self.settings, 1161)
        self.assertEqual(len(self.sent), 1)
        self.assertNotIn('secret', (self.root/'remote-notification-status.json').read_text())

    def test_disable_cancels_queued_delivery(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100)
        self.settings['enabled'] = False
        self.engine.dispatch(self.settings, 1100)
        self.assertEqual(self.sent, [])

    def test_manual_receipt_and_changed_deadline_send_one_alert(self):
        self.engine.observe(self.sample(), self.settings, 900)
        receipt = dict(requestID='r2', accountKey='A', state='completed', outcome='reset', at=1100)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100, receipt)
        self.engine.dispatch(self.settings, 1100)
        self.engine.dispatch(self.settings, 1101)
        self.assertEqual(len(self.sent), 1)

    def test_quota_update_before_manual_reply_does_not_double_notify(self):
        self.engine.observe(self.sample(), self.settings, 900)
        receipt = dict(requestID='pending-reset', accountKey='A', state='pending', at=1100)
        self.engine.observe(self.sample(2000, 0, at=1101), self.settings, 1101, receipt)
        self.engine.dispatch(self.settings, 1101)
        self.assertEqual(self.sent, [])
        receipt.update(state='completed', outcome='reset', at=1102)
        self.engine.observe(self.sample(2000, 1, at=1102), self.settings, 1102, receipt)
        self.engine.dispatch(self.settings, 1102)
        self.assertEqual(len(self.sent), 1)
        self.assertIn('重置券', self.sent[0][2])

    def test_three_failures_stop_retrying(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100)
        calls = []
        def fail(*a): calls.append(a); raise OSError('offline')
        self.engine.deliver = fail
        for at in (1100, 1161, 1282, 2000):
            self.engine.dispatch(self.settings, at)
        self.assertEqual(len(calls), 3)
        self.assertIn('停止重试', (self.root/'remote-notification-status.json').read_text())

    def test_stale_read_and_unrelated_manual_receipts_are_ignored(self):
        self.engine.observe(self.sample(), self.settings, 900)
        receipt = dict(requestID='r3', accountKey='B', state='completed', outcome='reset', at=1100)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 2000, receipt)
        self.engine.dispatch(self.settings, 2000)
        self.assertEqual(self.sent, [])

    def test_account_switch_cancels_unsent_old_account_event(self):
        self.engine.observe(self.sample(), self.settings, 900)
        self.engine.observe(self.sample(2000, 0, at=1100), self.settings, 1100)
        self.engine.observe(self.sample(3000, account='B', at=1101), self.settings, 1101)
        self.engine.dispatch(self.settings, 1101)
        self.assertEqual(self.sent, [])

    def test_service_worker_waits_for_fresh_account_confirmation(self):
        from codex_pulse.remote_notifications import RemoteNotifications
        restarted = RemoteNotifications(self.root, deliver=lambda *a: self.sent.append(a))
        self.assertFalse(restarted.ready(1100))
        restarted.observe(self.sample(at=1100), self.settings, 1100)
        self.assertTrue(restarted.ready(1101))
        self.assertFalse(restarted.ready(1300))
        restarted.invalidate()
        self.assertFalse(restarted.ready(1101))

    def inventory_sample(self, *, used=90, ids=('v1', 'v2'), expiry=5000, at=900, account='A'):
        value = self.sample(reset=4000, used=used, at=at, account=account)
        value.update(resetCredits=len(ids), resetVouchers=[dict(id=i, expiresAt=expiry) for i in ids])
        return value

    def test_external_voucher_consumption_and_recovery_send_once(self):
        self.engine.observe(self.inventory_sample(), self.settings, 900)
        after = self.inventory_sample(used=1, ids=('v2',), at=920)
        self.engine.observe(after, self.settings, 920)
        self.engine.dispatch(self.settings, 920)
        self.engine.observe(after, self.settings, 921)
        self.engine.dispatch(self.settings, 921)
        self.assertEqual(len(self.sent), 1)
        self.assertIn('外部手动重置', self.sent[0][2])

    def test_external_evidence_can_arrive_in_either_order_across_restart(self):
        from codex_pulse.remote_notifications import RemoteNotifications
        for recovery_first in (False, True):
            with self.subTest(recovery_first=recovery_first), tempfile.TemporaryDirectory() as root:
                sent = []
                engine = RemoteNotifications(Path(root), deliver=lambda *a: sent.append(a))
                engine.observe(self.inventory_sample(), self.settings, 900)
                intermediate = self.inventory_sample(used=1 if recovery_first else 90,
                                                      ids=('v1', 'v2') if recovery_first else ('v2',), at=920)
                engine.observe(intermediate, self.settings, 920)
                engine.dispatch(self.settings, 920)
                self.assertEqual(sent, [])
                engine = RemoteNotifications(Path(root), deliver=lambda *a: sent.append(a))
                engine.observe(self.inventory_sample(used=2, ids=('v2',), at=940), self.settings, 940)
                engine.dispatch(self.settings, 940)
                self.assertEqual(len(sent), 1)

    def test_expired_unknown_or_inconsistent_inventory_is_not_external_reset(self):
        cases = [('expired', 910), ('unknown', None), ('mismatch', 5000), ('boolean', 5000)]
        from codex_pulse.remote_notifications import RemoteNotifications
        for kind, expiry in cases:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as root:
                sent = []
                engine = RemoteNotifications(Path(root), deliver=lambda *a: sent.append(a))
                before = self.inventory_sample(expiry=expiry)
                after = self.inventory_sample(used=1, ids=('v2',), at=920)
                if kind == 'mismatch': after['resetCredits'] = 0
                if kind == 'boolean': before['resetCredits'] = True
                engine.observe(before, self.settings, 900)
                engine.observe(after, self.settings, 920)
                engine.dispatch(self.settings, 920)
                self.assertEqual(sent, [])

    def test_natural_reset_and_inventory_loss_do_not_claim_external_reset(self):
        before = self.inventory_sample()
        before['windows'] = core.normalize(usage(90, reset=910))
        self.engine.observe(before, self.settings, 900)
        after = self.inventory_sample(used=1, ids=('v2',), at=920)
        self.engine.observe(after, self.settings, 920)
        self.engine.dispatch(self.settings, 920)
        self.assertEqual(len(self.sent), 1)
        self.assertIn('自然重置', self.sent[0][2])

    def test_external_reset_respects_manual_toggle_and_account_binding(self):
        self.settings['manual'] = False
        self.engine.observe(self.inventory_sample(), self.settings, 900)
        self.engine.observe(self.inventory_sample(used=1, ids=('v2',), at=920), self.settings, 920)
        self.engine.dispatch(self.settings, 920)
        self.assertEqual(self.sent, [])
        self.settings['manual'] = True
        self.engine.observe(self.inventory_sample(), self.settings, 950)
        self.engine.observe(self.inventory_sample(used=1, ids=('v2',), at=970, account='B'), self.settings, 970)
        self.engine.dispatch(self.settings, 970)
        self.assertEqual(self.sent, [])

    def test_voucher_loss_without_recovery_does_not_notify_later_unrelated_change(self):
        self.engine.observe(self.inventory_sample(), self.settings, 900)
        self.engine.observe(self.inventory_sample(ids=('v2',), at=920), self.settings, 920)
        self.engine.dispatch(self.settings, 920)
        self.assertEqual(self.sent, [])
        self.engine.observe(self.inventory_sample(used=1, ids=('v2',), at=1700), self.settings, 1700)
        self.engine.dispatch(self.settings, 1700)
        self.assertEqual(self.sent, [])

    def test_local_receipt_before_quota_inventory_change_does_not_double_notify(self):
        self.engine.observe(self.inventory_sample(), self.settings, 900)
        receipt = dict(requestID='local-rpc', accountKey='A', state='completed', outcome='reset', at=920)
        self.engine.observe(self.inventory_sample(at=920), self.settings, 920, receipt)
        self.engine.dispatch(self.settings, 920)
        self.engine.observe(self.inventory_sample(used=1, ids=('v2',), at=940), self.settings, 940, receipt)
        self.engine.dispatch(self.settings, 940)
        self.assertEqual(len(self.sent), 1)

    def test_local_pending_inventory_change_and_completion_do_not_double_notify(self):
        self.engine.observe(self.inventory_sample(), self.settings, 900)
        receipt = dict(requestID='local-pending', accountKey='A', state='pending', at=920)
        self.engine.observe(self.inventory_sample(used=1, ids=('v2',), at=920), self.settings, 920, receipt)
        self.engine.dispatch(self.settings, 920)
        self.assertEqual(self.sent, [])
        receipt.update(state='completed', outcome='reset', at=940)
        self.engine.observe(self.inventory_sample(used=2, ids=('v2',), at=940), self.settings, 940, receipt)
        self.engine.dispatch(self.settings, 940)
        self.assertEqual(len(self.sent), 1)


class TransportTests(unittest.TestCase):
    @patch('codex_pulse.remote_notifications.credentials')
    @patch('codex_pulse.remote_notifications.build_opener')
    def test_bark_posts_unicode_and_requires_service_acceptance(self, opener, secrets):
        from codex_pulse.remote_notifications import deliver_remote
        import json
        secrets.return_value = dict(pushURL='https://push.example/device-key')
        response = opener.return_value.open.return_value.__enter__.return_value
        response.read.return_value = b'{"code":200}'
        deliver_remote(dict(channel='push'), '标题', '额度重置', 'event')
        request = opener.return_value.open.call_args.args[0]
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(json.loads(request.data)['body'], '额度重置')
        response.read.return_value = b'{"code":400}'
        with self.assertRaises(ValueError): deliver_remote(dict(channel='push'), 'title', 'body', 'event')
        secrets.return_value = dict(pushURL='http://push.example/key')
        with self.assertRaises(ValueError): deliver_remote(dict(channel='push'), 'title', 'body', 'event')

    @patch('codex_pulse.remote_notifications.credentials')
    @patch('codex_pulse.remote_notifications.smtplib.SMTP_SSL')
    @patch('codex_pulse.remote_notifications.smtplib.SMTP')
    def test_email_uses_verified_tls_and_stable_message_id(self, starttls, smtp_ssl, secrets):
        from codex_pulse.remote_notifications import deliver_remote
        secrets.return_value = dict(smtpPassword='test-password')
        settings = dict(channel='email', smtpHost='smtp.example', sender='a@example.com', recipient='b@example.com', smtpPort='465')
        client = smtp_ssl.return_value.__enter__.return_value
        client.send_message.return_value = {}
        deliver_remote(settings, 'title', 'body', 'event')
        message = client.send_message.call_args.args[0]
        self.assertEqual(message['To'], 'b@example.com')
        client.login.assert_called_once_with('a@example.com', 'test-password')
        self.assertTrue(smtp_ssl.call_args.kwargs['context'].check_hostname)
        settings.update(smtpTLS='starttls', smtpPort='587')
        client = starttls.return_value.__enter__.return_value
        client.send_message.return_value = {}
        deliver_remote(settings, 'title', 'body', 'event')
        client.starttls.assert_called_once()
        self.assertEqual(client.send_message.call_args.args[0]['Message-ID'], message['Message-ID'])


if __name__ == '__main__':
    unittest.main()
