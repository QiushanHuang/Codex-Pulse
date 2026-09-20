import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch
from scripts import install_macos

class InstallTests(unittest.TestCase):
    def run_install(self, running, copy):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with patch.object(install_macos, 'ROOT', root), patch.object(install_macos, 'TARGET', root/'Applications/Codex Pulse.app'), \
                 patch.object(install_macos, 'read_signature', return_value={'identifier':'local.qiushan.CodexPulse','cdhash':'new'}), \
                 patch.object(install_macos, 'build_report', return_value={}), \
                 patch.object(install_macos.subprocess, 'run', side_effect=lambda args,**kw:CompletedProcess(args,0 if running or 'pgrep' not in args[0] else 1)), \
                 patch.object(install_macos.shutil, 'copytree', copy):
                install_macos.install(root/'build/Codex Pulse.app')

    def test_running_app_is_rejected_before_creating_any_duplicate(self):
        from unittest.mock import Mock
        copy=Mock()
        with self.assertRaisesRegex(RuntimeError, '退出'):
            self.run_install(True,copy)
        copy.assert_not_called()

    def test_staging_preserves_app_name_outside_applications(self):
        from unittest.mock import Mock
        copy=Mock(side_effect=RuntimeError('stop before copying'))
        with self.assertRaisesRegex(RuntimeError,'stop before copying'):
            self.run_install(False,copy)
        destination=copy.call_args.args[1]
        self.assertEqual(destination.name,'Codex Pulse.app')
        self.assertIn('.install-staging',destination.parts)
        self.assertNotIn('Applications',destination.parts)
