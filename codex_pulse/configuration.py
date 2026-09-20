"""Transactional config edits shared with the native app via config.lock.

The native app owns schema/profile migration; CLI edits retain unknown fields.
"""
from contextlib import contextmanager
import fcntl
import json
from pathlib import Path

from .monitor import atomic


@contextmanager
def edit_config(directory):
    directory=Path(directory)
    directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (directory/'config.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        path=directory/'config.json'
        try:
            config=json.loads(path.read_text()) if path.exists() else {}
            if not isinstance(config,dict):
                raise ValueError('设置文件必须为对象')
            version=config.get('schemaVersion',1)
            if type(version) is not int or not 1 <= version <= 2:
                raise ValueError('设置文件版本不受支持')
            if not isinstance(config.get('deviceProfiles',{}),dict):
                raise ValueError('设备配置格式不正确')
            if not isinstance(config.get('lightSettings',{}),dict):
                raise ValueError('灯光配置格式不正确')
            for profile in config.get('deviceProfiles',{}).values():
                if not isinstance(profile,dict) or not isinstance(profile.get('lightSettings',{}),dict):
                    raise ValueError('设备配置格式不正确')
            yield config
            atomic(path,config)
        finally:
            fcntl.flock(lock,fcntl.LOCK_UN)
