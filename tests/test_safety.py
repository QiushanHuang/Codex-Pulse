import tempfile
from pathlib import Path
import unittest
from codex_pulse.codex import AppServer, event_tail


class AdapterSafety(unittest.TestCase):
    def test_monitor_rejects_turns_and_redemption(self):
        adapter = AppServer('/not-launched')
        for method in ('turn/start','thread/resume','account/rateLimitResetCredit/consume'):
            with self.assertRaises(ValueError):
                adapter.call(method)

    def test_tail_ignores_partial_json_and_message_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'log.jsonl'
            path.write_text('{incomplete}\n'+
                '{"type":"event_msg","timestamp":"2026-09-12T00:00:00Z","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"secret"}}\n'+
                '{"type":"response_item","payload":{"text":"secret"}}\n')
            events = event_tail(path)
            self.assertEqual(len(events),1)
            self.assertNotIn('secret',str(events))


if __name__=='__main__':unittest.main()
