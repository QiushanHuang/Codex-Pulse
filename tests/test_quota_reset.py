import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

try:
    from codex_pulse.quota_reset import execute_reset
except ImportError:
    execute_reset = None


class FakeServer:
    def __init__(self, outcome='reset', count=2, email='test@example.invalid'):
        self.outcome, self.count, self.email = outcome, count, email
        self.redemptions = []
    def start(self): pass
    def close(self): pass
    def call(self, method, params=None):
        if method == 'account/read': return {'account': {'type': 'chatgpt', 'email': self.email}}
        if method == 'account/rateLimits/read': return {'rateLimitResetCredits': {'availableCount': self.count}}
        if method == 'account/rateLimitResetCredit/consume':
            self.redemptions.append(params)
            if isinstance(self.outcome, Exception): raise self.outcome
            return {'outcome': self.outcome}
        raise AssertionError(method)


class ResetTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(execute_reset, 'explicit reset gateway is not implemented')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.key = hashlib.sha256(b'test@example.invalid').hexdigest()
        self.request = str(uuid4())
    def run_reset(self, server, request=None, confirmed=True, key=None):
        return execute_reset(server, self.root, request or self.request, key or self.key, confirmed=confirmed)
    def test_confirmation_and_account_binding_are_required(self):
        server = FakeServer()
        self.assertEqual(self.run_reset(server, confirmed=False)['state'], 'rejected')
        self.assertEqual(self.run_reset(server, key='a'*64)['state'], 'rejected')
        self.assertEqual(server.redemptions, [])
    def test_success_is_recorded_and_duplicate_request_is_not_sent(self):
        server = FakeServer()
        self.assertEqual(self.run_reset(server)['outcome'], 'reset')
        self.assertEqual(self.run_reset(server)['outcome'], 'reset')
        self.assertEqual(server.redemptions, [{'idempotencyKey': self.request}])
        status=json.loads((self.root / f'quota-reset-{self.key}.json').read_text())
        self.assertEqual(status['state'], 'completed')
    def test_uncertain_attempt_blocks_new_key_and_reuses_same_key_even_if_count_is_zero(self):
        server = FakeServer(TimeoutError())
        self.assertEqual(self.run_reset(server)['state'], 'unknown')
        self.assertEqual(self.run_reset(server, request=str(uuid4()))['state'], 'blocked')
        self.assertEqual(len(server.redemptions), 1)
        server.outcome, server.count = 'alreadyRedeemed', 0
        self.assertEqual(self.run_reset(server)['outcome'], 'alreadyRedeemed')
        self.assertEqual(server.redemptions[0], server.redemptions[1])
    def test_no_credit_does_not_send_mutation(self):
        server=FakeServer(count=0)
        self.assertEqual(self.run_reset(server)['outcome'], 'noCredit')
        self.assertEqual(server.redemptions, [])
    def test_nothing_to_reset_and_unknown_outcomes_are_not_reported_as_success(self):
        self.assertEqual(self.run_reset(FakeServer('nothingToReset'))['outcome'], 'nothingToReset')
        self.assertEqual(self.run_reset(FakeServer('futureOutcome'), request=str(uuid4()))['state'], 'unknown')
    def test_invalid_identifiers_do_not_reach_service(self):
        server=FakeServer()
        self.assertEqual(self.run_reset(server, request='../escape')['state'], 'rejected')
        self.assertEqual(self.run_reset(server, key='not-account')['state'], 'rejected')
        self.assertEqual(server.redemptions, [])

    def test_account_switch_during_preflight_is_rejected(self):
        class SwitchingServer(FakeServer):
            reads=0
            def call(self,method,params=None):
                if method=='account/read':
                    self.reads+=1
                    if self.reads>1:self.email='other@example.invalid'
                return super().call(method,params)
        server=SwitchingServer()
        self.assertEqual(self.run_reset(server)['state'],'rejected')
        self.assertEqual(server.redemptions,[])
    def test_concurrent_attempt_is_blocked_before_network(self):
        import fcntl
        server=FakeServer()
        with (self.root/'quota-reset.lock').open('a') as held:
            fcntl.flock(held,fcntl.LOCK_EX|fcntl.LOCK_NB)
            self.assertEqual(self.run_reset(server)['state'],'blocked')
        self.assertEqual(server.redemptions,[])
