import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CLI = Path(__file__).resolve().parents[1] / 'scripts/pulse.py'


class SettingsPersistenceTests(unittest.TestCase):
    def test_light_toggle_preserves_color_brightness_and_speed(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'config.json'
            settings = {'globalBrightness': .4, 'otherColor': '#AACCFF', 'cycleSeconds': 20}
            file.write_text(json.dumps({'lighting': False, 'lightSettings': settings, 'preview': {'scene': 'low'}}))
            for action in ('lights-on', 'lights-off'):
                result = subprocess.run([sys.executable, str(CLI), action, '--data-dir', directory], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                config = json.loads(file.read_text())
                self.assertEqual(config.get('lightSettings'), settings)
                self.assertNotIn('preview', config)

    def test_preview_three_tasks_preserves_actual_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'config.json'
            settings = {'keypadBrightness': .5, 'cycleSeconds': 20}
            file.write_text(json.dumps({'lighting': True, 'lightSettings': settings}))
            result = subprocess.run([sys.executable, str(CLI), 'preview', '--scene', 'running', '--tasks', '3', '--data-dir', directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(file.read_text())
            self.assertEqual(config['preview']['taskCount'], 3)
            self.assertEqual(config['preview']['duration'], 22)
            self.assertEqual(config['lightSettings'], settings)


if __name__ == '__main__':
    unittest.main()

class CorruptConfigurationTests(unittest.TestCase):
    def test_mutating_cli_rejects_corrupt_settings_without_overwriting(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'config.json'; original='{broken settings'
            file.write_text(original)
            result=subprocess.run([sys.executable,str(CLI),'lights-on','--data-dir',directory],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(file.read_text(),original)
