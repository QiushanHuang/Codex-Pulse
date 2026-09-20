"""Bounded hand-off of exclusive monitor ownership; never unlink a live lock."""
import fcntl
import os
import time

class MonitorAlreadyRunning(RuntimeError):
    pass

class MonitorParentExited(RuntimeError):
    pass

def acquire_monitor_lock(path, timeout=25, poll_interval=.1, parent=None):
    # Opening with w would erase the owner's PID even when flock then fails.
    stream=path.open('a+')
    deadline=time.monotonic()+max(0,timeout)
    try:
        while True:
            if parent and os.getppid()!=parent:
                raise MonitorParentExited('监控启动已取消：应用已退出')
            try:
                fcntl.flock(stream,fcntl.LOCK_EX|fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining=deadline-time.monotonic()
                if remaining<=0:
                    stream.seek(0);owner=stream.read(64).strip()
                    owner=owner if owner.isdigit() else '未知'
                    raise MonitorAlreadyRunning(f'监控锁仍被其他后台占用（记录 PID {owner}）；等待交接超时')
                time.sleep(min(max(.01,poll_interval),remaining))
        stream.seek(0);stream.truncate();stream.write(str(os.getpid()));stream.flush()
        return stream
    except BaseException:
        stream.close()
        raise
