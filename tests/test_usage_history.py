import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from codex_pulse.monitor import History


def quota(balance, account='A', used=20, reset=1000):
    return {'accountId': account, 'rateLimitsByLimitId': {'codex': {
        'primary': {'usedPercent': used, 'windowDurationMins': 300, 'resetsAt': reset},
        'credits': {'balance': balance, 'unlimited': False}}}}


class UsageHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'history.sqlite'
        self.history = History(self.path)
        self.addCleanup(self.history.close)

    def test_credit_observations_are_persisted_not_only_the_latest_snapshot(self):
        self.history.observe(quota('100'), 100)
        self.history.observe(quota('75'), 160)
        tables = {row[0] for row in self.history.db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        self.assertIn('credit_observations', tables, 'Credit history must survive the monitor and app restarting')
        rows = self.history.db.execute('SELECT at,balance FROM credit_observations ORDER BY at').fetchall()
        self.assertEqual(rows, [(100, 100), (160, 75)])

    def report(self, start=99, end=1000, account='A', task=None):
        import hashlib
        from codex_pulse.usage_history import query
        key=hashlib.sha256(account.encode()).hexdigest()
        return query(self.path, key, start, end, task)

    def test_drop_refill_zero_unknown_and_account_isolation(self):
        for at,balance in [(100,100),(160,75),(220,150),(280,0),(340,None),(400,500)]:
            self.history.observe(quota(balance),at)
        self.history.observe(quota(10000,'B'),450)
        self.history.observe(quota(9999,'B'),510)
        result=self.report()
        self.assertEqual(result['credit']['decreased'],175)
        self.assertEqual(result['credit']['increased'],75)
        self.assertEqual([p['value'] for p in result['creditPoints']],[100,75,150,0,500])
        self.assertNotEqual(result['creditPoints'][-1]['segment'],result['creditPoints'][-2]['segment'])
        self.assertEqual(self.report(account='B')['credit']['decreased'],1)
        self.assertEqual(result['tasks'],[])
        self.assertIsNone(self.report(start=1000,end=1100)['credit']['decreased'])

    def test_no_invented_credit_before_baseline_or_across_query_boundary(self):
        self.history.observe(quota(100),100)
        self.history.observe(quota(50),200)
        self.assertIsNone(self.report(150,250)['credit']['decreased'])
        self.assertEqual(self.report(100,250)['credit']['decreased'],50)
        self.assertIsNone(self.report(50,99)['credit']['decreased'])

    def test_partial_pushes_do_not_retimestamp_old_credit_balance(self):
        self.history.observe(quota(100),100)
        self.history.observe(quota(100),150,record_credit=False)
        self.assertEqual(self.history.db.execute('SELECT count(*) FROM credit_observations').fetchone()[0],1)

    def test_offline_gap_keeps_delta_but_does_not_invent_a_current_speed(self):
        self.history.observe(quota(100),100)
        self.history.observe(quota(25),900)
        result=self.report()
        self.assertEqual(result['credit']['decreased'],75)
        self.assertEqual(result['credit']['gaps'],1)
        self.assertIsNone(result['credit']['perHour'])
        self.assertNotEqual(result['creditPoints'][0]['segment'],result['creditPoints'][1]['segment'])

    def test_query_survives_restart_and_is_read_only(self):
        self.history.observe(quota(100),100)
        self.history.observe(quota(90),160)
        before=self.path.read_bytes()
        self.assertEqual(self.report()['credit']['decreased'],10)
        self.assertEqual(before,self.path.read_bytes())
        other=History(self.path)
        try:
            self.assertEqual(other.db.execute('SELECT count(*) FROM credit_observations').fetchone()[0],2)
        finally:
            other.close()

    def task_sample(self, at, count, tid='one', observations=None):
        from codex_pulse.usage_history import observe_tasks
        observe_tasks(self.history.db,[dict(id=tid,title='Task '+tid,tokensUsed=count)],
                      observations or [dict(taskId=tid,at=at,tokensUsed=count)],at)

    def test_task_counters_are_deltas_not_summed_and_speed_uses_time(self):
        for at,total in [(100,1000),(160,1120),(220,1300)]:
            self.task_sample(at,total)
        self.task_sample(220,1300)
        result=self.report()
        self.assertEqual(result['tokens'],300)
        self.assertEqual(result['tasks'][0]['perMinute'],150)
        self.assertEqual(sum(p['value'] for p in result['tokenPoints']),300)
        self.assertEqual(result['tasks'][0]['samples'],3)

    def test_counter_corrections_and_task_filters_do_not_fake_usage(self):
        for at,total in [(100,1000),(160,1100),(220,20),(280,50)]:
            self.task_sample(at,total)
        for at,total in [(100,300),(160,500)]:
            self.task_sample(at,total,'two')
        result=self.report(task='one')
        self.assertEqual(result['tokens'],130)
        self.assertEqual(result['tokenAdjustments'],1)
        self.assertEqual(len(result['tasks']),2)
        self.assertEqual(self.report()['tokens'],330)
        self.assertIsNone(self.report(110,170,task='one')['tokens'])
        self.assertIsNone(self.report(task='missing')['tokens'])

    def test_baseline_and_missing_counters_are_unknown_not_zero(self):
        from codex_pulse.usage_history import observe_tasks
        observe_tasks(self.history.db,[dict(id='missing',title='Unknown')],[],100)
        self.task_sample(200,8000)
        observe_tasks(self.history.db,[dict(id='one',title='Task one',tokensUsed=8000)],[],250)
        result=self.report()
        self.assertIsNone(result['tokens'])
        self.assertIsNone(result['tasks'][0]['tokens'])
        self.assertIsNone(result['tasks'][0]['perMinute'])
        self.assertEqual(result['tasks'][0]['samples'],1)

    def test_invalid_ranges_and_unknown_database(self):
        from codex_pulse.usage_history import query
        for start,end in [(10,10),(20,10),(-1,20),(0,float('nan')),(0,float('inf'))]:
            with self.assertRaises(ValueError):
                query(self.path,'A',start,end)
        result=query(Path(self.temp.name)/'missing.sqlite','A',10,20)
        self.assertEqual(result['tasks'],[])
        self.assertFalse((Path(self.temp.name)/'missing.sqlite').exists())

    def test_chart_density_is_bounded_and_preserves_extrema_and_future_history(self):
        from codex_pulse.usage_history import compact
        points=[dict(at=i,value=1000 if i==501 else -100 if i==502 else 5,segment=0) for i in range(3000)]
        data=compact(points,0,3000)
        self.assertLessEqual(len(data),480)
        self.assertEqual(min(p['value'] for p in data),-100)
        self.assertEqual(max(p['value'] for p in data),1000)
        self.history.observe(quota(100),100)
        self.history.observe(quota(90),100+90*86400)
        self.assertEqual(self.history.db.execute('SELECT count(*) FROM samples').fetchone()[0],2)

    def test_session_metadata_ingestion_keeps_token_event_times_and_drains_once(self):
        from codex_pulse.codex import LocalTasks
        from codex_pulse.usage_history import observe_tasks
        root=Path(self.temp.name)/'codex'
        log=root/'sessions'/'sample.jsonl'
        log.parent.mkdir(parents=True)
        events=[]
        for second,total in [(0,1000),(30,1100),(59,1250)]:
            events.append(json.dumps(dict(type='event_msg',timestamp=f'2026-10-23T01:00:{second:02d}Z',
                payload=dict(type='token_count',info=dict(total_token_usage=dict(total_tokens=total)),private='never persist'))))
        log.write_text('\n'.join(events)+'\n')
        with sqlite3.connect(root/'state_5.sqlite') as db:
            db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived,tokens_used)')
            db.execute('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',('one',None,'Test',str(log),100,0,1250))
        reader=LocalTasks(root)
        tasks=reader.read()
        observations=reader.take_usage_observations()
        self.assertEqual([o['tokensUsed'] for o in observations],[1000,1100,1250])
        self.assertEqual(set(observations[0]),{'taskId','at','tokensUsed'})
        observe_tasks(self.history.db,tasks,observations,1792717260)
        reader.read()
        self.assertEqual(reader.take_usage_observations(),[])
        from codex_pulse.usage_history import query
        result=query(self.path,'A',1792717200,1792717260)
        self.assertEqual(result['tokens'],250)
        self.assertAlmostEqual(result['tasks'][0]['perMinute'],250/59*60)

    def test_unknown_or_unlimited_credit_breaks_consumption_intervals(self):
        self.history.observe(quota(100),100)
        raw=quota(50);raw['rateLimitsByLimitId']['codex']['credits']['unlimited']=True
        self.history.observe(raw,160)
        self.history.observe(quota(0),220)
        self.assertIsNone(self.report()['credit']['decreased'])

    def test_equal_timestamp_corrections_keep_event_order(self):
        for at,total in [(100,1000),(160,1100),(160,20),(220,50)]:
            self.task_sample(at,total)
        self.assertEqual(self.report()['tokens'],130)
        self.assertEqual(self.report()['tokenAdjustments'],1)
