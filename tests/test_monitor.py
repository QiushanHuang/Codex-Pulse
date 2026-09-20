import tempfile
from pathlib import Path
import unittest
from codex_pulse.monitor import History
from test_core import usage


class HistoryTests(unittest.TestCase):
    def test_history_warms_up_and_persists_across_restart(self):
        with tempfile.TemporaryDirectory() as d:
            h = History(Path(d) / 'history.sqlite')
            h.observe(usage(10), 100)
            out = h.observe(usage(12), 700)
            self.assertEqual(out['windows'][0]['burnRate'], 12)
            h.close()
            h = History(Path(d) / 'history.sqlite')
            out = h.observe(usage(13), 1000)
            self.assertEqual(out['windows'][0]['burnRate'], 12)
            h.close()

    def test_switching_accounts_cannot_create_reset(self):
        with tempfile.TemporaryDirectory() as d:
            h = History(Path(d) / 'history.sqlite')
            h.observe(usage(95), 100)
            other = usage(0)
            other['accountId'] = 'account-B'
            out = h.observe(other, 700)
            self.assertEqual(out['newEvents'], [])
            self.assertIsNone(out['windows'][0]['burnRate'])
            h.close()


if __name__ == '__main__':
    unittest.main()
