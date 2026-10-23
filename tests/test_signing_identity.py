import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from scripts import signing_identity as signing

CERT={'sha1':'A'*40,'name':'Apple Development: Example (TEST)'}
OTHER={'sha1':'B'*40,'name':'Apple Development: Another (TEST)'}
SIGNED={'identifier':signing.APP_ID,'team':'TESTTEAM','requirement':'identifier "local.qiushan.CodexPulse" and anchor apple generic','cdhash':'old'}
PROFILE={'version':1,**CERT,**SIGNED}
ADHOC={'identifier':signing.APP_ID,'team':'not set','requirement':'cdhash H"abc"','cdhash':'abc'}


class SigningIdentityTests(unittest.TestCase):
    def test_pin_wins_over_other_available_signers(self):
        self.assertEqual(signing.select_signing_identity(available=[OTHER,CERT],profile=PROFILE),CERT)

    def test_no_silent_fallback_when_fixed_certificate_is_missing(self):
        for identities in ([],[OTHER]):
            with self.assertRaisesRegex(RuntimeError,'不会自动'):
                signing.select_signing_identity(available=identities,profile=PROFILE)
        with self.assertRaisesRegex(RuntimeError,'不会退回'):
            signing.select_signing_identity(available=[],installed=SIGNED)
        with self.assertRaisesRegex(RuntimeError,'不能改回'):
            signing.select_signing_identity('-',available=[CERT],profile=PROFILE)

    def test_explicit_identity_is_resolved_once_and_ambiguity_requires_selection(self):
        self.assertEqual(signing.select_signing_identity(CERT['name'],available=[OTHER,CERT]),CERT)
        with self.assertRaisesRegex(RuntimeError,'多个'):
            signing.select_signing_identity(available=[OTHER,CERT])
        with self.assertRaisesRegex(RuntimeError,'不可用'):
            signing.select_signing_identity('missing',available=[CERT])

    def test_clean_ci_host_can_build_without_claiming_a_persistent_identity(self):
        self.assertEqual(signing.select_signing_identity(available=[])['sha1'],'-')
        self.assertEqual(signing.select_signing_identity('-',available=[CERT])['sha1'],'-')
        self.assertFalse(signing.certificate_signed(ADHOC))

    def test_successful_pin_roundtrip_and_corrupt_profiles_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'signing.json'
            self.assertIsNone(signing.load_profile(path))
            signing.pin_identity(CERT,SIGNED,path)
            self.assertEqual(signing.load_profile(path),PROFILE)
            for value in ('broken',json.dumps({'version':1}),json.dumps({**PROFILE,'sha1':'bad'}),json.dumps({**PROFILE,'identifier':'other.app'})):
                path.write_text(value)
                with self.assertRaisesRegex(RuntimeError,'不会退回'):
                    signing.load_profile(path)

    def test_authority_is_checked_by_requirement_not_changing_hash(self):
        with patch.object(signing,'compare',return_value='matches') as compare:
            signing.ensure_compatible('/tmp/new.app',SIGNED)
            compare.assert_called_once_with('/tmp/new.app',SIGNED)
        for state in ('changed','unknown'):
            with patch.object(signing,'compare',return_value=state):
                with self.assertRaisesRegex(RuntimeError,'保留输入监控授权'):
                    signing.ensure_compatible('/tmp/new.app',SIGNED)
        signing.ensure_compatible('/tmp/new.app',ADHOC)
        with patch.object(signing,'compare',return_value='changed'):
            signing.ensure_compatible('/tmp/new.app',SIGNED,allow_change=True)

    def test_unverified_signature_can_never_be_pinned(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'profile.json'
            with self.assertRaisesRegex(RuntimeError,'有效证书'):
                signing.pin_identity(CERT,ADHOC,path)
            self.assertFalse(path.exists())
