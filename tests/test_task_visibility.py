import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from codex_pulse.codex import LocalTasks


class TaskVisibilityTests(unittest.TestCase):
    def setup_rows(self,root,modern=True):
        (root/'sessions').mkdir()
        log=root/'sessions/work.jsonl';log.write_text('')
        db=sqlite3.connect(root/'state_5.sqlite')
        db.execute('CREATE TABLE threads (id,name,title,rollout_path,updated_at,archived,source'+
                   (',thread_source,model' if modern else '')+')')
        return db,log

    def test_internal_and_unnamed_rows_do_not_consume_visible_limit(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();db,log=self.setup_rows(root)
            rows=[
                ('g1',None,'Guardian review',str(log),100,0,json.dumps({'subagent':{'other':'guardian'}}),'guardian_review','codex-auto-review'),
                ('g2',None,'Renamed reviewer',str(log),99,0,json.dumps({'subagent':{'other':'guardian'}}),'subagent','codex-auto-review'),
                ('empty',None,'   ',str(log),98,0,'vscode','subagent','gpt-6-astra'),
                ('real',None,'My work',str(log),97,0,'vscode','user','gpt-6-astra'),
                ('named',None,'Guardian review',str(log),96,0,'vscode','user','gpt-6-astra')]
            db.executemany('INSERT INTO threads VALUES(?,?,?,?,?,?,?,?,?)',rows);db.commit();db.close()
            self.assertEqual([r['id'] for r in LocalTasks(root).read(limit=1)],['real'])
            self.assertEqual({r['id'] for r in LocalTasks(root).read()},{'real','named'})

    def test_legacy_source_marker_works_without_new_schema_fields(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d).resolve();db,log=self.setup_rows(root,False)
            db.executemany('INSERT INTO threads VALUES(?,?,?,?,?,?,?)',[
                ('g',None,'Guardian review',str(log),100,0,json.dumps({'subagent':{'other':'guardian'}})),
                ('real',None,'My work',str(log),90,0,'vscode')]);db.commit();db.close()
            self.assertEqual([r['id'] for r in LocalTasks(root).read(limit=1)],['real'])


if __name__=='__main__':unittest.main()
