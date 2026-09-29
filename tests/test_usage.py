import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from codex_pulse import core
from codex_pulse.codex import LocalTasks
from codex_pulse.monitor import History


class UsageTests(unittest.TestCase):
    def test_credit_balance_is_not_quota_or_reset_coupons(self):
        with tempfile.TemporaryDirectory() as directory:
            history = History(Path(directory) / 'history.sqlite')
            try:
                raw = {'rateLimitsByLimitId': {'codex': {'credits': {
                    'hasCredits': True, 'unlimited': False, 'balance': '123.45'}}},
                    'rateLimitResetCredits': {'availableCount': 2}}
                result = history.observe(raw, 100)
                self.assertEqual(result.get('credits'), {'balance': 123.45, 'unlimited': False})
                self.assertEqual(result['resetCredits'], 2)
                self.assertIsNone(history.observe({}, 101).get('credits'))
            finally:
                history.close()

    def test_credit_zero_unknown_unlimited_and_invalid(self):
        normalize = getattr(core, 'normalize_credits', lambda _: None)
        def value(balance, unlimited=False):
            return normalize({'rateLimits': {'credits': {'balance': balance, 'unlimited': unlimited}}})
        self.assertEqual(value('0'), {'balance': 0, 'unlimited': False})
        self.assertEqual(value('-1'), {'balance': -1, 'unlimited': False})
        self.assertEqual(value(None, True), {'balance': None, 'unlimited': True})
        for invalid in (None, True, 'NaN', 'Infinity', 'bad'):
            self.assertEqual(value(invalid), {'balance': None, 'unlimited': False})
        self.assertIsNone(normalize({'rateLimitsByLimitId': {'spark': {'credits': {'balance': '9'}}}}))

    def test_task_total_is_latest_cumulative_value_not_sum_of_events(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            (root / 'sessions').mkdir()
            log = root / 'sessions/test.jsonl'
            def event(total):
                return json.dumps({'type': 'event_msg', 'timestamp': '2026-09-29T01:00:00Z',
                    'payload': {'type': 'token_count', 'info': {'total_token_usage': {
                        'total_tokens': total, 'input_tokens': total - 100, 'output_tokens': 100,
                        'cached_input_tokens': 200, 'reasoning_output_tokens': 20},
                        'secret': 'message content'}}}) + '\n'
            log.write_text(event(500) + event(700) + event(700))
            with sqlite3.connect(root / 'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id, name, title, rollout_path, updated_at, archived, tokens_used)')
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?)', ('task', None, 'Test', str(log), 100, 0, 680))
            reader = LocalTasks(root)
            task = reader.read()[0]
            self.assertEqual(task.get('tokensUsed'), 700)
            self.assertEqual(task.get('inputTokens'), 600)
            self.assertEqual(task.get('outputTokens'), 100)
            self.assertNotIn('secret', str(reader.cache))
            log.write_text('')
            self.assertEqual(reader.read()[0].get('tokensUsed'), 680)
            log.unlink()
            self.assertEqual(reader.read()[0].get('tokensUsed'), 680)

    def test_old_database_and_missing_usage_are_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with sqlite3.connect(root / 'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id, name, title, rollout_path, updated_at, archived)')
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?)', ('task', None, 'Test', str(root / 'sessions/missing'), 100, 0))
            self.assertIsNone(LocalTasks(root).read()[0].get('tokensUsed'))
