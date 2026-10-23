"""Local observed usage, independent of service billing and per-task Credit attribution."""
from contextlib import closing
import argparse
import json
import math
from pathlib import Path
import sqlite3
import time

from .core import number, token_integer

SCHEMA = '''
CREATE TABLE IF NOT EXISTS credit_observations (
 account TEXT NOT NULL, at REAL NOT NULL, balance REAL, unlimited INTEGER NOT NULL,
 PRIMARY KEY(account,at));
CREATE TABLE IF NOT EXISTS task_token_observations (
 task TEXT NOT NULL, at REAL NOT NULL, total INTEGER NOT NULL,
 PRIMARY KEY(task,at,total));
CREATE TABLE IF NOT EXISTS usage_tasks (task TEXT PRIMARY KEY, title TEXT NOT NULL);
CREATE INDEX IF NOT EXISTS task_token_time ON task_token_observations(at,task);
'''


def initialize(db):
    db.executescript(SCHEMA)


def observe_credit(db, account, credits, at):
    if not number(at) or not account:
        return
    credits = credits or {}
    balance = credits.get('balance')
    db.execute('INSERT OR IGNORE INTO credit_observations VALUES(?,?,?,?)',
               (account, at, balance if number(balance) else None, bool(credits.get('unlimited'))))


def observe_tasks(db, tasks, observations, at):
    """First cumulative counters are baselines, never historical interval consumption."""
    for task in tasks:
        if not isinstance(task.get('id'), str):
            continue
        db.execute('INSERT INTO usage_tasks VALUES(?,?) ON CONFLICT(task) DO UPDATE SET title=excluded.title WHERE title<>excluded.title',
                   (task['id'], str(task.get('title') or '未命名任务')[:512]))
    for sample in observations:
        if isinstance(sample.get('taskId'), str) and number(sample.get('at')) and token_integer(sample.get('tokensUsed')):
            db.execute('INSERT OR IGNORE INTO task_token_observations VALUES(?,?,?)',
                       (sample['taskId'], sample['at'], sample['tokensUsed']))
    for task in tasks:
        if not token_integer(task.get('tokensUsed')) or not isinstance(task.get('id'), str):
            continue
        # SQLite-only totals have no trustworthy token event timestamp. Record changes
        # at observation time rather than inventing a historical consumption time.
        latest = db.execute('SELECT total FROM task_token_observations WHERE task=? ORDER BY at DESC,rowid DESC LIMIT 1',
                            (task['id'],)).fetchone()
        if latest is None or latest[0] != task['tokensUsed']:
            db.execute('INSERT OR IGNORE INTO task_token_observations VALUES(?,?,?)',
                       (task['id'], at, task['tokensUsed']))
    db.commit()


def compact(points, start, end, limit=480):
    """Keep first, last and extrema per bucket, including segment boundaries."""
    if len(points) <= limit:
        return points
    buckets = {}
    width = max(1, (end-start)/max(1, limit//4))
    for p in points:
        buckets.setdefault((int((p['at']-start)/width), p.get('segment', 0)), []).append(p)
    result = []
    for group in buckets.values():
        selected = [group[0], min(group, key=lambda p:p['value']), max(group, key=lambda p:p['value']), group[-1]]
        result.extend(sorted({p['at']:p for p in selected}.values(), key=lambda p:p['at']))
    # Never join unrelated segments when the chart is dense.
    if len(result) > limit:
        essential=[result[0],min(result,key=lambda p:p['value']),max(result,key=lambda p:p['value']),result[-1]]
        sparse=result[::math.ceil(len(result)/max(1,limit-4))]
        result=sorted({(p['at'],p.get('segment',0)):p for p in sparse+essential}.values(),key=lambda p:p['at'])
    return result


def query(path, account, start, end, task_id=None):
    if not number(start) or not number(end) or not 0 <= start < end <= 253402300799:
        raise ValueError('起止时间无效；结束时间必须晚于开始时间。')
    if not isinstance(account, str) or not 0 < len(account) <= 256:
        raise ValueError('当前账号不可用。')
    result = dict(start=start, end=end, generatedAt=time.time(), creditPoints=[], creditChanges=[], quotas=[],
                  tokenPoints=[], tasks=[], credit=dict(decreased=None, increased=None, perHour=None, gaps=0),
                  tokens=None, tokenPerMinute=None, tokenAdjustments=0, bucketSeconds=max(60, (end-start)/240),
                  recordedFrom=None, accountRecordedFrom=None, taskRecordedFrom=None)
    path = Path(path).resolve()
    if not path.exists():
        return result
    with closing(sqlite3.connect(path.as_uri()+'?mode=ro', uri=True, timeout=3)) as db:
        db.execute('PRAGMA query_only=ON')
        names = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if 'credit_observations' in names:
            first = db.execute('SELECT MIN(at) FROM credit_observations WHERE account=?',(account,)).fetchone()[0]
            result['accountRecordedFrom'] = first
            rows = db.execute('SELECT at,balance,unlimited FROM credit_observations WHERE account=? AND at>=? AND at<=? ORDER BY at',
                              (account,start,end))
            points, changes, prev, segment, decrease, increase, seconds, pairs = [], [], None, 0, 0., 0., 0., 0
            for at,balance,unlimited in rows:
                valid = number(balance) and not unlimited
                if not valid:
                    prev=None;segment+=1
                    continue
                if prev:
                    delta, duration = prev[1]-balance, at-prev[0]
                    if duration > 0:
                        pairs+=1;decrease+=max(0,delta);increase+=max(0,-delta)
                        if delta:
                            changes.append(dict(at=at,value=max(0,delta),refill=max(0,-delta),segment=segment))
                        if duration>600:
                            result['credit']['gaps']+=1;segment+=1
                        else:
                            seconds+=duration
                points.append(dict(at=at,value=balance,segment=segment));prev=(at,balance)
            result['creditPoints']=compact(points,start,end)
            result['creditChanges']=compact(changes,start,end)
            result['credit'].update(decreased=decrease if pairs else None,increased=increase if pairs else None,
                                    perHour=decrease/seconds*3600 if seconds and not result['credit']['gaps'] else None)
        if 'samples' in names:
            windows = {}
            for window,at,used,reset,data in db.execute('SELECT window,at,used,reset,data FROM samples WHERE account=? AND at>=? AND at<=? ORDER BY at',
                                                       (account,start,end)):
                if not number(used):
                    continue
                if window not in windows:
                    metadata=json.loads(data)
                    windows[window]=dict(id=window,label=f"{metadata.get('name','Codex')} · {metadata.get('label',window)}",points=[])
                points=windows[window]['points']
                segment=points[-1]['segment'] if points else 0
                if points and (at-points[-1]['at']>600 or 100-used>points[-1]['value']):
                    segment+=1
                points.append(dict(at=at,value=100-used,segment=segment))
            result['quotas']=[{**w,'points':compact(w['points'],start,end)} for w in windows.values()]
        if 'task_token_observations' in names:
            result['taskRecordedFrom']=db.execute('SELECT MIN(at) FROM task_token_observations').fetchone()[0]
            summaries, previous, bins = {}, {}, {}
            total, pairs, span, adjustments = 0,0,0.,0
            rows=db.execute('SELECT o.task,o.at,o.total,COALESCE(t.title, o.task) FROM task_token_observations o LEFT JOIN usage_tasks t ON o.task=t.task WHERE o.at>=? AND o.at<=? ORDER BY o.task,o.at,o.rowid',(start,end))
            for tid,at,counter,title in rows:
                row=summaries.setdefault(tid,dict(id=tid,title=title,tokens=None,perMinute=None,firstAt=at,lastAt=at,samples=0,adjustments=0))
                row['samples']+=1;row['lastAt']=at
                if tid in previous:
                    before,old=previous[tid]
                    if counter<old:
                        row['adjustments']+=1
                        if task_id is None or tid==task_id:
                            adjustments+=1
                    elif at>before:
                        delta=counter-old
                        row['tokens']=(row['tokens'] or 0)+delta
                        if task_id is None or tid==task_id:
                            total+=delta;pairs+=1
                            if delta:
                                bucket=min(239,int((at-start)/result['bucketSeconds']))
                                bins[bucket]=bins.get(bucket,0)+delta
                previous[tid]=(at,counter)
            for row in summaries.values():
                duration=row['lastAt']-row['firstAt']
                if duration>0 and row['tokens'] is not None:
                    row['perMinute']=row['tokens']/duration*60
            selected=[r for r in summaries.values() if task_id is None or r['id']==task_id]
            lower=min((r['firstAt'] for r in selected),default=end)
            upper=max((r['lastAt'] for r in selected),default=start)
            result.update(tokens=total if pairs else None,tokenPerMinute=total/(upper-lower)*60 if pairs and upper>lower else None,
                          tokenAdjustments=adjustments,
                          tokenPoints=[dict(at=min(end,start+(i+0.5)*result['bucketSeconds']),value=v,
                                            perMinute=v/result['bucketSeconds']*60,segment=0) for i,v in sorted(bins.items())],
                          tasks=sorted(summaries.values(),key=lambda r:-(r['tokens'] or 0)))
        origins=[v for v in (result['accountRecordedFrom'],result['taskRecordedFrom']) if v is not None]
        result['recordedFrom']=min(origins) if origins else None
    return result


def main():
    parser=argparse.ArgumentParser(description='Read-only local usage query')
    parser.add_argument('--data-dir',default=str(Path.home()/'Library/Application Support/CodexPulse'))
    parser.add_argument('--account',required=True)
    parser.add_argument('--start',required=True,type=float)
    parser.add_argument('--end',required=True,type=float)
    parser.add_argument('--task')
    args=parser.parse_args()
    result=query(Path(args.data_dir)/'history.sqlite',args.account,args.start,args.end,args.task)
    print(json.dumps(result,ensure_ascii=False,allow_nan=False))


if __name__=='__main__':
    main()
