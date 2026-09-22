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

class WidgetRegistrationTests(unittest.TestCase):
    def test_refresh_removes_stale_source_and_replaces_target_registration(self):
        target=Path('/Applications/Codex Pulse.app')
        source=Path('/tmp/build/Codex Pulse.app')
        with patch.object(install_macos,'TARGET',target), patch.object(install_macos.subprocess,'run',return_value=CompletedProcess([],0,stdout='',stderr='')) as run:
            install_macos.refresh_widget_registration(source)
        calls=[call.args[0] for call in run.call_args_list]
        extension='Contents/PlugIns/CodexPulseWidget.appex'
        self.assertIn(['/usr/bin/pluginkit','-r',str(source/extension)],calls)
        self.assertIn(['/usr/bin/pluginkit','-r',str(target/extension)],calls)
        add=['/usr/bin/pluginkit','-a',str(target/extension)]
        self.assertEqual(calls[-1],add)
        self.assertTrue(all(call.kwargs.get('check') for call in run.call_args_list if '-r' not in call.args[0]))
        self.assertFalse(any('killall' in str(c) or '-kill' in c for c in calls))

    def test_same_source_never_unregisters_installed_host(self):
        with patch.object(install_macos.subprocess,'run',return_value=CompletedProcess([],0,stdout='',stderr='')) as run:
            install_macos.refresh_widget_registration(install_macos.TARGET)
        calls=[call.args[0] for call in run.call_args_list]
        self.assertFalse(any('-u' in call for call in calls))

    def test_already_absent_registration_is_safe_to_repeat(self):
        extension=Path('/tmp/Widget.appex')
        result=CompletedProcess([],1,stdout='',stderr=f'remove: no plugin at {extension}\n')
        with patch.object(install_macos.subprocess,'run',return_value=result):
            install_macos.remove_widget_registration(extension)

    def test_registration_removal_does_not_swallow_other_errors(self):
        import subprocess
        result=CompletedProcess([],1,stdout='',stderr='permission denied')
        with patch.object(install_macos.subprocess,'run',return_value=result):
            with self.assertRaises(subprocess.CalledProcessError):
                install_macos.remove_widget_registration(Path('/tmp/Widget.appex'))
