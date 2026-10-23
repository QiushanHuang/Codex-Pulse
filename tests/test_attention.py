import json
from pathlib import Path
import tempfile
import unittest

from codex_pulse import core, monitor
from codex_pulse import attention


TID = '01a0f1d2-8966-7f21-8a81-497d93a1dfab'


class AttentionTests(unittest.TestCase):
    def test_permissions_are_signals_never_decisions_or_command_copies(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            payload = dict(session_id=TID, turn_id='turn', hook_event_name='PermissionRequest',
                           tool_name='Bash', tool_input={'command': 'secret command'})
            attention.record(p, payload, now=100)
            tasks = attention.overlay(p, [dict(id=TID, status='active', turnId='turn', at=99,
                                              approvalReviewer='user')], now=104)
            self.assertEqual(tasks[0]['status'], 'waiting_approval')
            self.assertNotIn('secret', (p / 'task-attention.json').read_text())
            self.assertNotIn('decision', (p / 'task-attention.json').read_text())
            attention.record(p, {**payload, 'hook_event_name': 'PostToolUse',
                                 'tool_use_id': 'call', 'tool_response': 'private output'}, now=105)
            self.assertEqual(attention.overlay(p, tasks, now=106)[0]['status'], 'active')

    def test_async_question_survives_immediate_tool_return_until_user_answers(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            event = dict(session_id=TID, turn_id='turn', tool_use_id='q',
                         tool_name='request_user_input_async', tool_input={'questions': ['secret']})
            attention.record(p, {**event, 'hook_event_name': 'PreToolUse'}, now=100)
            attention.record(p, {**event, 'hook_event_name': 'PostToolUse'}, now=101)
            task = dict(id=TID, status='completed', turnId='turn', at=102)
            self.assertEqual(attention.overlay(p, [task], now=103)[0]['status'], 'waiting_input')
            attention.record(p, dict(session_id=TID, turn_id='turn', hook_event_name='UserPromptSubmit'), now=104)
            self.assertEqual(attention.overlay(p, [task], now=105)[0]['status'], 'completed')

    def test_unrelated_parallel_tool_cannot_clear_pending_request(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            e = dict(session_id=TID, turn_id='turn', tool_name='Bash', tool_input={'command': 'one'})
            attention.record(p, {**e, 'hook_event_name': 'PermissionRequest'}, now=100)
            attention.record(p, {**e, 'hook_event_name': 'PostToolUse', 'tool_input': {'command': 'two'}}, now=101)
            task = dict(id=TID, status='active', turnId='turn', at=99, approvalReviewer='user')
            self.assertEqual(attention.overlay(p, [task], now=104)[0]['status'], 'waiting_approval')
            self.assertEqual(attention.overlay(p, [{**task, 'turnId': 'next', 'at': 105}], now=106)[0]['status'], 'active')

    def test_startup_and_repeated_snapshot_do_not_replay_finished_tasks(self):
        old = {TID: dict(id=TID, title='Work', status='active', turnId='t', at=99)}
        task = {**old[TID], 'status': 'completed', 'at': 100}
        self.assertEqual(monitor.task_events(None, [task], 101), [])
        events = monitor.task_events(old, [task], 101)
        self.assertEqual(events[0]['taskId'], TID)
        self.assertEqual(monitor.task_events({TID: task}, [task], 102), [])
        task = {**task, 'status': 'waiting_input', 'attentionId': 'q', 'at': 103}
        self.assertEqual(monitor.task_events({TID: {**task, 'status': 'active'}}, [task], 104)[0]['kind'], 'waiting_input')

    def test_adaptive_quota_policy_and_read_only_notification_whitelist(self):
        self.assertEqual(monitor.quota_interval([]), 120)
        self.assertEqual(monitor.quota_interval([{'status': 'active'}]), 15)
        self.assertEqual(monitor.quota_interval([{'status': 'waiting_input'}]), 120)
        from codex_pulse.codex import AppServer
        server = AppServer('/not-launched')
        self.assertFalse(server.accept_notification({'method': 'item/permissions/requestApproval', 'id': 4}))
        self.assertTrue(server.accept_notification({'method': 'account/rateLimits/updated',
                                                     'params': {'rateLimits': {'primary': {}}}}))
        self.assertEqual(server.notifications.get_nowait()['method'], 'account/rateLimits/updated')

    def test_existing_pending_request_is_actionable_on_startup_without_replaying_endings(self):
        pending=dict(id=TID,title='Work',status='waiting_input',turnId='t',attentionId='q',at=10)
        events=monitor.task_events(None,[pending],1000)
        self.assertEqual(len(events),1)
        self.assertEqual(events[0]['at'],1000)
        self.assertEqual(monitor.task_events(None,[{**pending,'status':'completed'}],1000),[])

    def test_hook_config_merge_is_idempotent_and_preserves_other_hooks(self):
        existing = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'my existing hook'}]}]},
                    'other': True}
        merged = attention.merge_hooks(existing, '/path with spaces/python', '/app/hook.py', '/data')
        self.assertEqual(merged['hooks']['Stop'], existing['hooks']['Stop'])
        self.assertTrue(merged['other'])
        self.assertEqual(attention.merge_hooks(merged, '/path with spaces/python', '/app/hook.py', '/data'), merged)
        commands = [h['command'] for groups in merged['hooks'].values() for g in groups for h in g['hooks']]
        self.assertTrue(any("'/path with spaces/python'" in c for c in commands))

    def test_partial_quota_push_keeps_other_bucket_and_secondary_window(self):
        prior = {'accountId': 'a', 'rateLimitsByLimitId': {'codex': {'limitId': 'codex',
                 'primary': {'usedPercent': 1}, 'secondary': {'usedPercent': 20}},
                 'spark': {'primary': {'usedPercent': 30}}}}
        merged = monitor.merge_quota_push(prior, {'rateLimits': {'limitId': 'codex',
                 'primary': {'usedPercent': 2}}})
        self.assertEqual(merged['rateLimitsByLimitId']['codex']['secondary']['usedPercent'], 20)
        self.assertEqual(merged['rateLimitsByLimitId']['codex']['primary']['usedPercent'], 2)
        self.assertEqual(merged['rateLimitsByLimitId']['spark'], prior['rateLimitsByLimitId']['spark'])
        self.assertEqual(prior['rateLimitsByLimitId']['codex']['primary']['usedPercent'], 1)


if __name__ == '__main__':
    unittest.main()
