import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from codex_pulse.codex import LocalTasks, event_tail
from codex_pulse.core import task_state


def record(kind, payload, second=0):
    return json.dumps({'timestamp':f'2026-10-01T00:00:{second:02d}Z','type':kind,'payload':payload})+'\n'


class RecordedQuestionTests(unittest.TestCase):
    def test_async_request_survives_tool_return_and_turn_end_but_user_reply_clears_it(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'session.jsonl'
            text=record('event_msg',{'type':'task_started','turn_id':'turn'})
            text+=record('response_item',{'type':'function_call','name':'request_user_input_async','call_id':'q','arguments':'private question'},1)
            text+=record('response_item',{'type':'function_call_output','call_id':'q','output':'accepted'},2)
            text+=record('event_msg',{'type':'task_complete','turn_id':'turn'},3)
            p.write_text(text)
            events=event_tail(p);now=events[-1]['at']+10
            state=task_state(events,now)
            self.assertEqual(state['status'],'waiting_input')
            self.assertFalse(state.get('isRunning'))
            self.assertEqual(state.get('attentionId'),'q')
            self.assertNotIn('private question',str(events))
            p.write_text(text+record('response_item',{'type':'message','role':'user','content':'private answer'},4))
            self.assertEqual(task_state(event_tail(p),now)['status'],'completed')

    def test_sync_response_only_clears_its_matching_question(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'session.jsonl'
            text=record('event_msg',{'type':'task_started','turn_id':'turn'})
            text+=record('response_item',{'type':'function_call','name':'functions.request_user_input','call_id':'q'},1)
            text+=record('response_item',{'type':'function_call_output','call_id':'other'},2)
            p.write_text(text);events=event_tail(p)
            self.assertEqual(task_state(events,events[-1]['at']+1)['status'],'waiting_input')
            p.write_text(text+record('response_item',{'type':'function_call_output','call_id':'q'},3))
            events=event_tail(p)
            self.assertEqual(task_state(events,events[-1]['at']+1)['status'],'active')

    def test_plain_question_text_is_not_treated_as_a_pending_tool_request(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'session.jsonl'
            p.write_text(record('event_msg',{'type':'task_started','turn_id':'turn'})+
                         record('response_item',{'type':'message','role':'assistant','content':'Can you confirm?'},1))
            events=event_tail(p)
            self.assertEqual(task_state(events,events[0]['at']+10)['status'],'active')

    def test_incremental_cache_keeps_question_during_long_stream_then_resolves(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();(root/'sessions').mkdir();p=root/'sessions/test.jsonl'
            p.write_text(record('event_msg',{'type':'task_started','turn_id':'turn'})+
                         record('response_item',{'type':'function_call','name':'request_user_input_async','call_id':'q'},1))
            with sqlite3.connect(root/'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived)')
                db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?)',('task',None,'Test',str(p),0,0))
            reader=LocalTasks(root)
            from unittest.mock import patch
            at=event_tail(p)[0]['at']
            with patch('codex_pulse.codex.time.time',return_value=at+10):
                self.assertEqual(reader.read()[0]['status'],'waiting_input')
                self.assertTrue(reader.read()[0].get('isRunning'))
                from codex_pulse.attention import overlay
                from codex_pulse.monitor import quota_interval
                task=reader.read()[0]
                self.assertEqual(overlay(root,[task],at+10)[0]['status'],'waiting_input')
                self.assertEqual(quota_interval([task]),15)
                with p.open('a') as f:
                    for _ in range(250):f.write(record('event_msg',{'type':'token_count'},2))
                self.assertEqual(reader.read()[0]['status'],'waiting_input')
                self.assertLess(len(reader.cache['task'][1]),150)
                with p.open('a') as f:f.write(record('response_item',{'type':'message','role':'user','content':'private answer'},3))
                self.assertEqual(reader.read()[0]['status'],'active')
            self.assertNotIn('private answer',str(reader.cache))

    def test_startup_reads_bounded_history_beyond_old_half_megabyte_tail(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();(root/'sessions').mkdir();p=root/'sessions/test.jsonl'
            p.write_text(record('event_msg',{'type':'task_started','turn_id':'turn'})+
                         record('response_item',{'type':'function_call','name':'request_user_input_async','call_id':'q'},1)+
                         record('ignored',{'padding':'x'*700000},2)+record('event_msg',{'type':'token_count'},3))
            with sqlite3.connect(root/'state_5.sqlite') as db:
                db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived)')
                db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?)',('task',None,'Test',str(p),0,0))
            from unittest.mock import patch
            with patch('codex_pulse.codex.time.time',return_value=1790812820):
                self.assertEqual(LocalTasks(root).read()[0]['status'],'waiting_input')


if __name__ == '__main__':unittest.main()
