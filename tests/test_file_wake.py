import builtins
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest.mock import patch
from codex_pulse.codex import LocalTasks
from codex_pulse.codex import event_tail
from codex_pulse.file_wake import FileWake


class FileWakeTests(unittest.TestCase):
    def test_complete_last_json_record_without_newline_is_still_readable(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'session.jsonl'
            p.write_text(json.dumps({'type':'event_msg','timestamp':'2026-09-30T00:00:00Z',
                                    'payload':{'type':'task_complete'}}))
            self.assertEqual(len(event_tail(p)),1)

    def test_selected_atomic_write_wakes_but_unrelated_file_does_not(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            signal = threading.Event()
            watcher = FileWake(signal)
            if not watcher.queue:
                self.skipTest('macOS filesystem events required')
            try:
                target = root / 'selected.json'
                watcher.set_paths({target})
                (root / 'unrelated.json').write_text('noise')
                self.assertFalse(signal.wait(.1))
                temp = root / 'selected.tmp'
                temp.write_text('changed'); temp.replace(target)
                self.assertTrue(signal.wait(1))
                signal.clear();watcher.set_paths({target})
                temp.write_text('again');temp.replace(target)
                self.assertTrue(signal.wait(1), 'replaced files must be rearmed')
            finally:
                watcher.close()

    def test_changed_rollout_reads_only_append_and_preserves_partial_line(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            (root / 'sessions').mkdir()
            log = root / 'sessions/log.jsonl'
            def event(kind):
                return json.dumps({'type': 'event_msg', 'timestamp': '2026-09-30T00:00:00Z',
                                   'payload': {'type': kind, 'turn_id': 'turn'}}) + '\n'
            log.write_text('{"type":"ignored"}\n' * 20000 + event('task_started'))
            with sqlite3.connect(root / 'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived)')
                db.execute('INSERT INTO threads VALUES (?,?,?,?,?,?)', ('task',None,'Test',str(log),100,0))
            reader = LocalTasks(root)
            reader.read()
            with log.open('a') as f:
                completion = event('task_complete')
                f.write(completion[:-8])
            amounts = []
            class Tracking:
                def __init__(self, *args, **kwargs): self.file = builtins.open(*args, **kwargs)
                def __enter__(self): return self
                def __exit__(self,*args): return self.file.__exit__(*args)
                def __getattr__(self,key): return getattr(self.file,key)
                def read(self,*args):
                    value=self.file.read(*args);amounts.append(len(value));return value
            with patch('codex_pulse.codex.open', Tracking):
                reader.read()
                with log.open('a') as f:f.write(completion[-8:])
                self.assertEqual(reader.read()[0]['status'], 'completed')
            self.assertLess(sum(amounts), 1000, 'do not reparse the full 512 KiB tail each streaming update')


if __name__ == '__main__': unittest.main()
