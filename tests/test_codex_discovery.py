import unittest
from pathlib import Path
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

    def test_finds_nested_app_cli_without_shell_path(self):
        for root in ('/Applications', str(Path.home() / 'Applications')):
            for app in ('ChatGPT', 'Codex'):
                expected = f'{root}/{app}.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
                with self.subTest(path=expected), \
                     patch('codex_pulse.codex.Path.is_file', lambda p: str(p) == expected), \
                     patch('codex_pulse.codex.shutil.which', return_value=None):
                    try:
                        actual = AppServer().binary
                    except RuntimeError:
                        actual = None
                    self.assertEqual(actual, expected)

    def test_restart_rediscovers_after_app_moves(self):
        old = '/Applications/Codex.app/Contents/Resources/codex'
        new = '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
        available = {old}
        with patch('codex_pulse.codex.Path.is_file', lambda p: str(p) in available), \
             patch('codex_pulse.codex.shutil.which', return_value=None):
            server = AppServer()
            available.clear()
            available.add(new)
            with patch('codex_pulse.codex.subprocess.Popen', side_effect=RuntimeError('launch intercepted')) as launch:
                with self.assertRaisesRegex(RuntimeError, 'launch intercepted'):
                    server.start()
                self.assertEqual(launch.call_args.args[0][0], new)

    def test_restart_does_not_override_explicit_binary(self):
        with patch('codex_pulse.codex.subprocess.Popen', side_effect=FileNotFoundError) as launch:
            with self.assertRaises(FileNotFoundError):
                AppServer('/custom/codex').start()
            self.assertEqual(launch.call_args.args[0][0], '/custom/codex')
