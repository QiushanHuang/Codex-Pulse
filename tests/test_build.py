import tempfile
import unittest
from pathlib import Path
from scripts import build_macos


class RuntimeTests(unittest.TestCase):
    def test_skips_executable_that_cannot_run_python(self):
        with tempfile.TemporaryDirectory() as directory:
            broken = Path(directory) / 'python3'
            broken.write_text('#!/bin/sh\necho "Xcode license not accepted" >&2\nexit 69\n')
            broken.chmod(0o755)
            import sys
            self.assertEqual(build_macos.select_python([str(broken), sys.executable]), sys.executable)

    def test_rejects_when_no_runtime_works(self):
        with self.assertRaisesRegex(RuntimeError, 'Python'):
            build_macos.select_python(['/does/not/exist'])
