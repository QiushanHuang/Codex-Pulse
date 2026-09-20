import unittest
from scripts import input_continuity as continuity

class ContinuityTests(unittest.TestCase):
    def test_reads_designated_requirement_and_hash(self):
        value=continuity.parse_signature('Identifier=local.qiushan.CodexPulse\nCDHash=abc123\nTeamIdentifier=not set\n# designated => cdhash H"abc123"\n')
        self.assertEqual(value['requirement'], 'cdhash H"abc123"')
        self.assertEqual(value['cdhash'], 'abc123')

    def test_incomplete_signature_is_unknown(self):
        self.assertIsNone(continuity.parse_signature('Identifier=x\n'))

    def test_install_verification_rejects_stale_wrong_app_and_wrong_signature(self):
        signature={'cdhash':'new'}
        status={'at':101,'pid':55,'appPath':'/Applications/Codex Pulse.app','signature':signature,'state':'signature_changed_denied'}
        self.assertTrue(continuity.status_matches(status,signature,100,'/Applications/Codex Pulse.app'))
        for patch in ({'at':99},{'appPath':'/tmp/Copy.app'},{'signature':{'cdhash':'old'}},{'pid':None},{'state':None}):
            self.assertFalse(continuity.status_matches({**status,**patch},signature,100,'/Applications/Codex Pulse.app'))

    def test_codesign_uses_inline_requirement_and_not_hash_equality(self):
        from unittest.mock import patch
        from subprocess import CompletedProcess
        old={'requirement':'identifier "local.qiushan.CodexPulse"', 'cdhash':'old'}
        with patch.object(continuity.subprocess, 'run', return_value=CompletedProcess([],0,'','')) as run:
            self.assertEqual(continuity.compare('/tmp/new.app', old), 'matches')
            self.assertIn('=identifier "local.qiushan.CodexPulse"', run.call_args.args[0])
        with patch.object(continuity.subprocess, 'run', return_value=CompletedProcess([],1,'','code failed to satisfy specified code requirement(s)')):
            self.assertEqual(continuity.compare('/tmp/new.app', old), 'changed')
        with patch.object(continuity.subprocess, 'run', return_value=CompletedProcess([],1,'','invalid requirement specification')):
            self.assertEqual(continuity.compare('/tmp/new.app', old), 'unknown')
