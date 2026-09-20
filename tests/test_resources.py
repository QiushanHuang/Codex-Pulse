import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from codex_pulse.codex import LocalTasks


class TaskConnectionTests(unittest.TestCase):
    def test_connection_closed_after_each_poll_including_query_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'state_5.sqlite'
            db = sqlite3.connect(path)
            db.execute('CREATE TABLE threads (id, name, title, rollout_path, updated_at, archived)')
            db.close()
            reader = LocalTasks(directory)
            connect = sqlite3.connect
            connections = []

            def tracked(*args, **kwargs):
                connection = connect(*args, **kwargs)
                connections.append(connection)
                return connection

            with patch('codex_pulse.codex.sqlite3.connect', side_effect=tracked):
                for _ in range(3):
                    self.assertEqual(reader.read(), [])
                db = connect(path)
                db.execute('DROP TABLE threads')
                db.close()
                with self.assertRaises(sqlite3.OperationalError):
                    reader.read()
            for connection in connections:
                with self.assertRaises(sqlite3.ProgrammingError):
                    connection.execute('SELECT 1')
