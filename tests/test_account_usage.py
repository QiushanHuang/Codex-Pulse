import unittest
from codex_pulse import core
from codex_pulse.codex import AppServer


class AccountUsageTests(unittest.TestCase):
    def test_usage_read_is_allowed_but_still_requires_a_started_adapter(self):
        with self.assertRaisesRegex(RuntimeError, 'not started'):
            AppServer('/not-launched').call('account/usage/read')

    def test_preserves_service_dates_and_zero_without_copying_other_fields(self):
        normalize = getattr(core, 'normalize_account_usage', lambda _: None)
        result = normalize({'dailyUsageBuckets': [{'startDate': '2026-09-29', 'tokens': 0},
                                                {'startDate': '2026-09-28', 'tokens': 100}],
                            'summary': {'lifetimeTokens': 999}, 'secret': 'private'})
        self.assertEqual(result, {'days': [{'date': '2026-09-28', 'tokens': 100},
                                          {'date': '2026-09-29', 'tokens': 0}], 'lifetimeTokens': 999})

    def test_missing_dates_are_not_invented_and_invalid_series_is_rejected(self):
        normalize = getattr(core, 'normalize_account_usage', lambda _: None)
        self.assertEqual(normalize({'dailyUsageBuckets': [], 'summary': {}}), {'days': [], 'lifetimeTokens': None})
        self.assertIsNone(normalize({'dailyUsageBuckets': None}))
        for rows in ([{'startDate':'2026-02-30','tokens':1}],
                     [{'startDate':'2026-09-29','tokens':True}],
                     [{'startDate':'2026-09-29','tokens':-1}],
                     [{'startDate':'2026-09-29','tokens':2**63}],
                     [{'startDate':'2026-09-29','tokens':1}]*2):
            self.assertIsNone(normalize({'dailyUsageBuckets':rows}))

    def test_usage_cannot_cross_account_boundaries_and_failure_retains_stale_data(self):
        apply = getattr(core, 'apply_account_usage', lambda *_: None)
        snapshot = {'accountKey': 'A', 'usage': None}
        apply(snapshot, {'accountKey':'B','usage':{'days':[]}}, 100)
        self.assertIsNone(snapshot['usage'])
        apply(snapshot, {'accountKey':'A','usage':{'days':[{'date':'2026-09-29','tokens':123}]}}, 101)
        self.assertEqual(snapshot.get('usageAt'),101)
        apply(snapshot, {'accountKey':'A','error':'unavailable'}, 102)
        self.assertEqual(snapshot['usage']['days'][0]['tokens'],123)
        self.assertEqual(snapshot['usageError'],'unavailable')
        self.assertEqual(snapshot['usageAt'],101)


class ResetInventoryTests(unittest.TestCase):
    def test_inventory_keeps_unknown_distinct_from_empty_and_sanitizes_dates(self):
        normalize=getattr(core,'normalize_reset_vouchers',lambda _:None)
        self.assertIsNone(normalize({}))
        self.assertEqual(normalize({'rateLimitResetCredits':{'credits':[]}}),[])
        self.assertEqual(normalize({'rateLimitResetCredits':{'credits':[
            {'id':'one','status':'available','expiresAt':200,'grantedAt':100,'title':'Reset','secret':'private'},
            {'id':'used','status':'redeemed','expiresAt':400},
            {'id':'two','status':'available','expiresAt':float('nan')}
        ]}}),[{'id':'one','expiresAt':200,'grantedAt':100},{'id':'two','expiresAt':None,'grantedAt':None}])
