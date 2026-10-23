import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from codex_pulse.attention import overlay,record
from codex_pulse.codex import LocalTasks
from codex_pulse.core import task_state

TID='01a0f1d2-8966-7f21-8a81-497d93a1dfab'

class ApprovalRoutingTests(unittest.TestCase):
    def event(self,**changes):
        return dict(session_id=TID,turn_id='turn',hook_event_name='PermissionRequest',
                    tool_name='Bash',tool_input={'command':'private command','description':'approval reason'},**changes)

    def test_auto_review_is_not_a_human_action_even_during_a_long_command(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);record(p,self.event(),now=100)
            task=dict(id=TID,status='active',turnId='turn',at=101,approvalReviewer='auto_review')
            self.assertEqual(overlay(p,[task],now=101)[0]['status'],'active')
            self.assertEqual(overlay(p,[task],now=180)[0]['status'],'active')

    def test_manual_request_waits_briefly_but_still_notifies_when_unresolved(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);record(p,self.event(),now=100)
            task=dict(id=TID,status='active',turnId='turn',at=99,approvalReviewer='user')
            deadlines=[]
            self.assertEqual(overlay(p,[task],now=101,approval_deadlines=deadlines)[0]['status'],'active')
            self.assertEqual(deadlines,[103])
            self.assertEqual(overlay(p,[task],now=104)[0]['status'],'waiting_approval')

    def test_auto_review_does_not_hide_an_explicit_question(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);record(p,self.event(),now=100)
            record(p,dict(session_id=TID,turn_id='turn',hook_event_name='PreToolUse',
                          tool_name='request_user_input_async',tool_use_id='question',tool_input={}),now=101)
            task=dict(id=TID,status='active',turnId='turn',at=99,approvalReviewer='auto_review')
            deadlines=[]
            result=overlay(p,[task],now=102,approval_deadlines=deadlines)[0]
            self.assertEqual(result['status'],'waiting_input')
            self.assertEqual(result['attentionId'],'question')
            self.assertTrue(result['isRunning'])
            self.assertEqual(deadlines,[])

    def test_reviewer_does_not_leak_into_a_different_turn(self):
        events=[dict(type='task_started',turn_id='old',at=90),
                dict(type='turn_context',turn_id='old',approval_reviewer='user',at=91),
                dict(type='task_started',turn_id='new',at=100)]
        self.assertNotIn('approvalReviewer',task_state(events,now=101))
        events.append(dict(type='turn_context',turn_id='new',approval_reviewer='auto_review',at=101))
        self.assertEqual(task_state(events,now=102)['approvalReviewer'],'auto_review')

    def test_canonical_command_clears_despite_approval_only_description(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);record(p,self.event(),now=100)
            record(p,dict(session_id=TID,turn_id='turn',hook_event_name='PostToolUse',tool_name='Bash',
                          tool_input={'command':'private command'},tool_use_id='call'),now=110)
            self.assertEqual(json.loads((p/'task-attention.json').read_text())['pending'],[])

    def test_unknown_reviewer_is_not_asserted_to_require_human_permission(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);record(p,self.event(),now=100)
            task=dict(id=TID,status='active',turnId='turn',at=99)
            self.assertEqual(overlay(p,[task],now=130)[0]['status'],'active')

    def test_indexed_turn_metadata_is_read_when_context_is_outside_tail(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();(root/'sessions').mkdir();log=root/'sessions/test.jsonl'
            def r(kind,payload):return json.dumps({'type':kind,'timestamp':'2026-10-02T00:00:00Z','payload':payload})+'\n'
            log.write_text(r('event_msg',{'type':'task_started','turn_id':'turn'})+
                           r('turn_context',{'turn_id':'turn','approvals_reviewer':'auto_review'})+
                           r('ignored',{'padding':'x'*2200000})+r('event_msg',{'type':'token_count','turn_id':'turn'}))
            with closing(sqlite3.connect(root/'state_5.sqlite')) as db, db:
                db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived)')
                db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?)',(TID,None,'Work',str(log),0,0))
            with closing(sqlite3.connect(root/'thread_history_1.sqlite')) as db, db:
                db.execute('CREATE TABLE thread_turns(thread_id,turn_id,rollout_byte_offset)')
                db.execute('INSERT INTO thread_turns VALUES(?,?,?)',(TID,'turn',0))
            from unittest.mock import patch
            with patch('codex_pulse.codex.time.time',return_value=1790899210):
                reader=LocalTasks(root)
                self.assertEqual(reader.read()[0].get('approvalReviewer'),'auto_review')
                # An unchanged long-running turn costs no repeated indexed context reads.
                with patch('codex_pulse.codex.sqlite3.connect',wraps=sqlite3.connect) as connect:
                    self.assertEqual(reader.read()[0].get('approvalReviewer'),'auto_review')
                    self.assertEqual(connect.call_count,1)  # Only the normal task database.

if __name__=='__main__':unittest.main()
