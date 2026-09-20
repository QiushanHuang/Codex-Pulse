import fcntl
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from codex_pulse.monitor_lock import acquire_monitor_lock, MonitorAlreadyRunning

class MonitorLockTests(unittest.TestCase):
    def test_live_owner_rejected_without_erasing_its_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'monitor.lock'
            with path.open('w+') as owner:
                fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB)
                owner.write('12345');owner.flush()
                with self.assertRaises(MonitorAlreadyRunning):
                    acquire_monitor_lock(path,timeout=.04,poll_interval=.01)
                self.assertEqual(path.read_text(),'12345')

    def test_waits_for_previous_owner_cleanup_and_then_takes_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'monitor.lock'
            owner=path.open('w+');fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB)
            released=threading.Event()
            def release():
                time.sleep(.12);owner.close();released.set()
            thread=threading.Thread(target=release);thread.start()
            try:
                with acquire_monitor_lock(path,timeout=1,poll_interval=.01) as new:
                    self.assertTrue(released.wait(.1))
                    self.assertEqual(path.read_text(),str(os.getpid()))
                    with path.open('a+') as challenger:
                        with self.assertRaises(BlockingIOError):fcntl.flock(challenger,fcntl.LOCK_EX|fcntl.LOCK_NB)
            finally:thread.join()

    def test_dead_pid_text_does_not_block_unowned_lock_or_leave_trailing_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'monitor.lock';path.write_text('9999999999999999999')
            with acquire_monitor_lock(path,timeout=0):self.assertEqual(path.read_text(),str(os.getpid()))
            with acquire_monitor_lock(path,timeout=0):pass

    def test_wait_is_cancelled_if_owning_app_exits(self):
        from unittest.mock import patch
        from codex_pulse.monitor_lock import MonitorParentExited
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'monitor.lock'
            with path.open('w+') as owner:
                fcntl.flock(owner,fcntl.LOCK_EX|fcntl.LOCK_NB);owner.write('12345');owner.flush()
                with patch('codex_pulse.monitor_lock.os.getppid',side_effect=[100,101]):
                    with self.assertRaises(MonitorParentExited):
                        acquire_monitor_lock(path,timeout=10,poll_interval=.01,parent=100)
                self.assertEqual(path.read_text(),'12345')
