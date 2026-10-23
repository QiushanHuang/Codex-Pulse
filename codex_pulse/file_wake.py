"""Coalescible macOS filesystem wakeups; no polling thread on other platforms."""
import os
from pathlib import Path
import select
import threading


class FileWake:
    def __init__(self, wake):
        self.wake = wake
        self.lock = threading.Lock()
        self.closed = False
        self.targets = {}
        self.handles = {}
        self.queue = select.kqueue() if hasattr(select, 'kqueue') else None
        if self.queue:
            threading.Thread(target=self.run, daemon=True).start()

    @staticmethod
    def signature(path):
        try:
            stat = path.stat()
            return stat.st_ino, stat.st_size, stat.st_mtime_ns
        except OSError:
            return None

    def set_paths(self, paths):
        if not self.queue:
            return
        with self.lock:
            targets = {Path(p) for p in paths}
            self.targets = {p: self.targets.get(p, self.signature(p)) for p in targets}
            watched = {p if p.exists() else p.parent for p in targets}
            for p, (fd, identity) in list(self.handles.items()):
                signature = self.signature(p)
                if p not in watched or signature is None or signature[0] != identity:
                    os.close(fd)
                    del self.handles[p]
            for p in watched - self.handles.keys():
                fd = None
                try:
                    fd = os.open(p, os.O_RDONLY | getattr(os, 'O_EVTONLY', 0))
                    event = select.kevent(fd, filter=select.KQ_FILTER_VNODE,
                                         flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                                         fflags=select.KQ_NOTE_WRITE | select.KQ_NOTE_EXTEND |
                                         select.KQ_NOTE_RENAME | select.KQ_NOTE_DELETE)
                    self.queue.control([event], 0, 0)
                    self.handles[p] = (fd, os.fstat(fd).st_ino)
                except OSError:
                    if fd is not None:
                        os.close(fd)

    def run(self):
        while not self.closed:
            try:
                events = self.queue.control(None, 64, 15)
                if events:
                    with self.lock:
                        changed = False
                        for p, old in list(self.targets.items()):
                            new = self.signature(p)
                            if new != old:
                                self.targets[p] = new
                                changed = True
                    if changed:
                        self.wake.set()
            except (OSError, ValueError):
                return

    def close(self):
        self.closed = True
        if self.queue:
            self.queue.close()
        with self.lock:
            for fd, _ in self.handles.values():
                os.close(fd)
            self.handles.clear()
