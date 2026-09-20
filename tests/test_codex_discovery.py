import unittest
from unittest.mock import patch
from codex_pulse.codex import AppServer


class CodexDiscoveryTests(unittest.TestCase):
    def test_finds_standard_codex_app_without_shell_path(self):
        expected = '/Applications/Codex.app/Contents/Resources/codex'
        with patch('codex_pulse.codex.Path.is_file', lambda p: str(p) == expected), \
             patch('codex_pulse.codex.shutil.which', return_value=None):
            try:
                actual = AppServer().binary
            except RuntimeError:
                actual = None
            self.assertEqual(actual, expected)

    def test_explicit_binary_remains_authoritative(self):
        self.assertEqual(AppServer('/custom/codex').binary, '/custom/codex')
