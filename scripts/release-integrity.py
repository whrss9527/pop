#!/usr/bin/env python3
"""附件摘要辅助函数改编自 whrss9527/frit a8ecb68 scripts/release/check-release.py（MIT）。
保留App校验和与插件索引的各自协议，逐一核对本次完整附件的实际摘要。
"""
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile


def fail(message):
    raise ValueError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()



def checksums(path):
    result = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'([0-9A-Fa-f]{64})\s+\*?([A-Za-z0-9_.+-]+)', line)
        if not match or match[2] in ('.', '..', 'SHA256SUMS.txt') or match[2] in result:
            fail('SHA256SUMS.txt 含无效或重复的附件条目')
        result[match[2]] = match[1].lower()
    if not result:
        fail('SHA256SUMS.txt 没有附件校验和')
    return result



def assets(value):
    result = {}
    for asset in value['assets']:
        if not isinstance(asset, dict) or not isinstance(asset.get('name'), str) or asset['name'] in result:
            fail('远端发行附件信息无效或名称重复')
        result[asset['name']] = asset
    return result


def download(tag, name, directory, asset):
    # 文件名已由本地清单或校验和解析限制，不接受下载 glob 或路径穿越。
    subprocess.run(['gh', 'release', 'download', tag, '--pattern', name, '--dir', str(directory)], check=True)
    path = directory / name
    if not path.is_file() or path.stat().st_size != asset['size']:
        fail('远端附件下载大小不符：' + name)
    return path


def digest(asset):
    value = asset.get('digest')
    if value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(r'sha256:[0-9A-Fa-f]{64}', value):
        fail('远端附件摘要无效：' + asset['name'])
    return value[7:].lower()



def verify(tag, value, paths, sums):
    remote = assets(value)
    local = [*paths, sums]
    expected = {path.name for path in local}
    if len(expected) != len(local) or set(remote) != expected:
        fail('远端附件清单与本次完整清单不一致')
    with tempfile.TemporaryDirectory(prefix='pop-release-check-') as directory:
        for path in local:
            item = remote[path.name]
            if item.get('state') != 'uploaded' or type(item.get('size')) is not int or item['size'] != path.stat().st_size or item['size'] <= 0:
                fail('远端附件未完整上传：' + path.name)
            actual = digest(item)
            if actual is None:
                actual = sha256(download(tag, path.name, Path(directory), item))
            if actual != sha256(path):
                fail('远端附件与本次实际内容不一致：' + path.name)
