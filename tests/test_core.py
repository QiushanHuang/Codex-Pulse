import unittest
from codex_pulse import core


def usage(used=30, reset=9000, duration=10080):
    return {'accountId': 'account-A', 'rateLimitsByLimitId': {'codex': {
        'primary': {'usedPercent': used, 'resetsAt': reset, 'windowDurationMins': duration},
        'secondary': None}}}


class QuotaTests(unittest.TestCase):
    def test_weekly_primary_is_weekly(self):
        self.assertEqual(len(core.normalize(usage())), 1)
        w = core.normalize(usage())[0]
        self.assertEqual(w['label'], '每周')
        self.assertEqual(w['remaining'], 70)

    def test_missing_not_zero(self):
        self.assertEqual(core.normalize({'rateLimits': None}), [])
        self.assertEqual(core.normalize(usage(None)), [])

    def test_reset_requires_service_evidence(self):
        self.assertEqual(len(core.normalize(usage(90, 1000))), 1)
        old = core.normalize(usage(90, 1000))[0]
        self.assertIsNone(core.change_kind(old, old, 1100))
        self.assertEqual(core.change_kind(old, core.normalize(usage(0, 2000))[0], 1100), 'reset')

    def test_drop_is_recovery_not_reset(self):
        self.assertEqual(len(core.normalize(usage(90))), 1)
        a, b = core.normalize(usage(90))[0], core.normalize(usage(1))[0]
        self.assertEqual(core.change_kind(a, b, 100), 'recovery')

    def test_rate_percent_points_per_hour(self):
        points = [{'at': 0, 'used': 20, 'reset': 9000}, {'at': 600, 'used': 22, 'reset': 9000}]
        self.assertEqual(core.burn_rate(points), 12)

    def test_service_reset_timestamp_jitter_does_not_discard_history(self):
        points = [{'at': 0, 'used': 20, 'reset': 9000}, {'at': 600, 'used': 22, 'reset': 9001}]
        self.assertEqual(core.burn_rate(points), 12)

    def test_rate_has_warmup_and_no_reset_or_gap_crossing(self):
        self.assertIsNone(core.burn_rate([{'at': 0, 'used': 20, 'reset': 1}]))
        self.assertIsNone(core.burn_rate([{'at': 0, 'used': 90, 'reset': 1}, {'at': 600, 'used': 1, 'reset': 2}]))
        self.assertIsNone(core.burn_rate([{'at': 0, 'used': 20, 'reset': 1}, {'at': 1800, 'used': 30, 'reset': 1}]))

    def test_nonfinite_and_missing_duration_rejected(self):
        self.assertEqual(core.normalize(usage(float('nan'))), [])
        self.assertEqual(core.normalize(usage(5, duration=None)), [])


class TaskTests(unittest.TestCase):
    def test_explicit_completion(self):
        events = [{'type': 'task_started', 'at': 100, 'turn_id': 'a'}, {'type': 'task_complete', 'at': 200, 'turn_id': 'a'}]
        self.assertEqual(core.task_state(events, 210)['status'], 'completed')

    def test_new_turn_replaces_old_completion(self):
        events = [{'type': 'task_complete', 'at': 100, 'turn_id': 'a'}, {'type': 'task_started', 'at': 200, 'turn_id': 'b'}]
        self.assertEqual(core.task_state(events, 210)['status'], 'active')

    def test_old_activity_is_unconfirmed(self):
        self.assertEqual(core.task_state([{'type': 'item_completed', 'at': 100}], 2000)['status'], 'unknown')

    def test_abort_is_not_completion(self):
        self.assertEqual(core.task_state([{'type': 'turn_aborted', 'at': 100}], 200)['status'], 'interrupted')


if __name__ == '__main__':
    unittest.main()
