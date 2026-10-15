#!/usr/bin/env python3
"""按精确源码恢复草稿，核验全部本地/远端附件后按ID公开；公开发行保持只读。"""
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile


def module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), Path(__file__).with_name(name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


integrity = module('release-integrity')
policy = module('release-plan')
SHA = re.compile(r'[0-9a-f]{40}')
GATES = {'build-and-test (Xcode 16.4)', 'build-and-test (Xcode latest)',
         'launch-smoke (macos-15)', 'launch-smoke (macos-26)'}


def run(*args):
    return subprocess.check_output(args, text=True)


def documents(text):
    decoder = json.JSONDecoder()
    while text.strip():
        text = text.lstrip()
        value, length = decoder.raw_decode(text)
        yield value
        text = text[length:]


class Release:
    def __init__(self, version):
        if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-.][0-9A-Za-z.]+)?', version):
            raise ValueError('版本号无效')
        self.version = version
        self.tag = 'v' + version
        self.repo = os.environ['GITHUB_REPOSITORY']
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', self.repo):
            raise ValueError('仓库名称无效')

    def api(self, path, payload=None):
        args = ['gh', 'api', 'repos/' + self.repo + '/' + path]
        if payload is None:
            return json.loads(run(*args))
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json') as body:
            json.dump(payload, body); body.flush()
            return json.loads(run(*args, '--method', 'POST' if path in ('releases', 'git/refs') else 'PATCH', '--input', body.name))

    def pages(self, path, field=None):
        values = []
        count = 0
        for page in documents(run('gh', 'api', '--paginate', 'repos/' + self.repo + '/' + path)):
            count += 1
            rows = page[field] if field else page
            if not isinstance(rows, list): raise ValueError('分页数据格式无效')
            values.extend(rows)
        if not count: raise ValueError('未取得分页数据')
        return values

    def releases(self):
        rows = self.pages('releases?per_page=100')
        for row in rows:
            if not isinstance(row, dict) or type(row.get('draft')) is not bool or type(row.get('prerelease')) is not bool or not isinstance(row.get('tag_name'), str):
                raise ValueError('发行列表条目无效')
        return rows

    def find(self):
        values = [v for v in self.releases() if v['tag_name'] == self.tag]
        if len(values) > 1: raise ValueError('同标签存在多个发行')
        return self.snapshot(values[0]['id']) if values else None

    def snapshot(self, release_id):
        if type(release_id) is not int or release_id <= 0: raise ValueError('发行ID无效')
        value = self.api('releases/' + str(release_id))
        if value.get('id') != release_id or value.get('tag_name') != self.tag or type(value.get('draft')) is not bool or not isinstance(value.get('assets'), list):
            raise ValueError('发行ID/标签/状态发生变化')
        return value

    def tag_commit(self):
        rows = [line.split() for line in run('git', 'ls-remote', 'origin', 'refs/tags/' + self.tag, 'refs/tags/' + self.tag + '^{}').splitlines()]
        if any(len(row) != 2 or not SHA.fullmatch(row[0]) for row in rows): raise ValueError('远端标签无效')
        peeled = next((row[0] for row in rows if row[1] == 'refs/tags/' + self.tag + '^{}'), None)
        return peeled or next((row[0] for row in rows if row[1] == 'refs/tags/' + self.tag), None)

    def ensure_tag(self, source):
        tag = self.tag_commit()
        if tag is None:
            self.api('git/refs', dict(ref='refs/tags/' + self.tag, sha=source))
        if self.tag_commit() != source: raise ValueError('发行标签未绑定本次源码')

    def bound(self, snapshot, source, require_tag=False):
        if not SHA.fullmatch(source) or snapshot.get('target_commitish') != source or snapshot.get('prerelease') != (os.environ.get('PRERELEASE') == 'true'):
            raise ValueError('草稿未绑定精确源码；停止恢复')
        tag = self.tag_commit()
        if tag != source and (tag is not None or require_tag): raise ValueError('标签与受验证源码不一致')

    def validated(self, source):
        status = self.api('compare/' + source + '...main').get('status')
        if status not in ('ahead', 'identical'): raise ValueError('源码不属于main历史')
        runs = self.pages('actions/workflows/ci.yml/runs?branch=main&head_sha=' + source + '&per_page=100', 'workflow_runs')
        runs = [v for v in runs if v.get('head_sha') == source and v.get('head_branch') == 'main'
                and v.get('event') in ('push', 'schedule', 'workflow_dispatch')]
        if not runs: raise ValueError('没有该源码的main原生验证')
        latest = max(runs, key=lambda v: (v['run_number'], v.get('run_attempt', 1)))
        jobs = self.pages('actions/runs/' + str(latest['id']) + '/jobs?per_page=100', 'jobs')
        gates = {v['name']: v for v in jobs if v['name'] in GATES}
        if set(gates) != GATES or any(v.get('status') != 'completed' or v.get('conclusion') != 'success' for v in gates.values()):
            raise ValueError('精确源码的四项main原生门禁尚未全部通过')

    def prepare(self, target, dry_run=False):
        existing = self.find()
        if existing and not existing['draft']: raise ValueError('发行已公开，保持附件不变；修复请使用新补丁版本')
        if existing:
            source = existing.get('target_commitish', '')
            if not SHA.fullmatch(source): raise ValueError('旧草稿未记录精确源码，不能自动恢复')
            if target and self.api('commits/' + urllib.parse.quote(target, safe=''))['sha'] != source:
                raise ValueError('恢复请求与原草稿源码不同')
            self.bound(existing, source)
        else:
            source = self.api('commits/' + urllib.parse.quote(target or os.environ['GITHUB_SHA'], safe=''))['sha']
            if not SHA.fullmatch(source): raise ValueError('源码SHA无效')
            tag = self.tag_commit()
            if tag is not None and tag != source: raise ValueError('已有标签与本次源码不同')
        if not dry_run: self.validated(source)
        return source

    def allowed(self):
        if os.environ.get('PRERELEASE') == 'true' or os.environ.get('DRY_RUN') == 'true': return True
        if policy.first_heading(Path('CHANGELOG.md').read_text()) != self.version:
            raise ValueError('稳定版必须先提升对应的更新日志章节')
        return policy.stable_allowed(self.releases(), dt.datetime.now(dt.timezone.utc))

    def publish(self, source):
        self.validated(source)
        paths = inventory(self.version, source)
        sums = Path('dist/SHA256SUMS.txt')
        hashes = integrity.checksums(sums)
        if hashes != {paths[0].name: integrity.sha256(paths[0])}:
            raise ValueError('本地附件与完整校验和不一致')
        if not self.allowed(): print('稳定版延期：等待下个上海工作日额度'); return
        value = self.find()
        if value and not value['draft']: raise ValueError('发行已公开，停止覆盖附件')
        if not value:
            if self.tag_commit() not in (None, source): raise ValueError('创建前标签发生变化')
            value = self.api('releases', dict(tag_name=self.tag, target_commitish=source, draft=True,
                                            prerelease=os.environ.get('PRERELEASE') == 'true', name='Pop ' + self.version + ('（测试版）' if os.environ.get('PRERELEASE') == 'true' else ''),
                                            body=Path('notes.md').read_text()))
        release_id = value['id']
        value = self.snapshot(release_id)
        self.bound(value, source)
        if not value['draft']: raise ValueError('上传前发行已被公开')
        self.ensure_tag(source)
        current = self.snapshot(release_id)
        if not current['draft']: raise ValueError('上传前发行状态发生变化')
        self.bound(current, source, require_tag=True)
        subprocess.run(['gh', 'release', 'upload', self.tag, *map(str, paths), str(sums), '--repo', self.repo, '--clobber'], check=True)
        value = self.snapshot(release_id)
        self.bound(value, source)
        if not value['draft']: raise ValueError('附件验收前发行已被公开')
        integrity.verify(self.tag, value, paths, sums)
        if not self.allowed(): print('附件已验收，草稿保留至下个上海工作日'); return
        before_public = self.snapshot(release_id)
        if not before_public['draft']: raise ValueError('公开前发行状态发生变化，停止修改')
        self.bound(before_public, source)
        newer = any(not row['draft'] and not row['prerelease'] and
                    re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', row['tag_name']) and
                    tuple(map(int, row['tag_name'][1:].split('.'))) > tuple(map(int, self.version.split('.')))
                    for row in self.releases()) if os.environ.get('PRERELEASE') != 'true' else False
        payload = dict(draft=False, prerelease=os.environ.get('PRERELEASE') == 'true',
                       name='Pop ' + self.version + ('（测试版）' if os.environ.get('PRERELEASE') == 'true' else ''), body=Path('notes.md').read_text(),
                       make_latest='false' if os.environ.get('PRERELEASE') == 'true' or newer else 'true')
        self.api('releases/' + str(release_id), payload)
        value = self.snapshot(release_id)
        if value['draft']: raise ValueError('发行仍是草稿')
        self.bound(value, source, require_tag=True)
        integrity.verify(self.tag, value, paths, sums)
        if payload['make_latest'] == 'true' and self.api('releases/latest').get('id') != release_id:
            raise ValueError('公开后latest核验未通过')
        print('已发布到 https://github.com/' + self.repo + '/releases/tag/' + self.tag)


def inventory(version, source):
    root = Path('dist')
    app = root / ('Pop-' + version + '.zip')
    index_path = root / 'plugins' / ('plugins-' + version + '.json')
    index = json.loads(index_path.read_text())
    with zipfile.ZipFile(app) as archive:
        info = plistlib.loads(archive.read('Pop.app/Contents/Info.plist'))
    build = info.get('PopBuildID', '')
    if not isinstance(build, str) or not SHA.fullmatch(source): raise ValueError('构建标识或源码格式无效')
    suffix = build.removeprefix(version + '+')
    if info.get('CFBundleShortVersionString') != version or not re.fullmatch(r'[0-9a-f]{12,40}', suffix) or not source.startswith(suffix):
        raise ValueError('App版本/构建标识与源码不一致')
    if type(index.get('format')) is not int or index.get('format') != 1 or index.get('version') != version or index.get('build') != build:
        raise ValueError('插件索引与App构建不一致')
    declared = re.findall(r'^\s+POP_PLUGIN_ID:\s*([A-Za-z0-9_-]+)\s*$', Path('project.yml').read_text(), re.M)
    if not declared or len(declared) != len(set(declared)): raise ValueError('工程插件清单无效')
    entries = index.get('plugins', [])
    if not isinstance(entries, list) or {v['id'] for v in entries} != set(declared) or len(entries) != len(declared):
        raise ValueError('插件索引缺少工程插件或有重复项')
    paths = [app, index_path]
    for item in entries:
        plugin_id = item['id']
        if not re.fullmatch(r'[A-Za-z0-9_-]+', plugin_id) or item['file'] != 'plugin-' + plugin_id + '.zip': raise ValueError('插件文件名无效')
        bundle = item['bundle']
        if not isinstance(bundle, str) or Path(bundle).name != bundle or not bundle.endswith('.bundle'): raise ValueError('插件bundle名称无效')
        path = index_path.parent / item['file']
        if path.stat().st_size != item['size'] or integrity.sha256(path) != item['sha256']: raise ValueError('插件附件与索引不一致')
        with zipfile.ZipFile(path) as archive:
            metadata = plistlib.loads(archive.read(bundle + '/Contents/Info.plist'))
        if metadata.get('PopBuildID') != build or metadata.get('PopPluginID') != plugin_id: raise ValueError('插件ABI/标识与App不一致')
        paths.append(path)
    return paths


def main():
    mode, version = sys.argv[1:3]
    release = Release(version.removeprefix('v'))
    if mode == 'prepare':
        print('ref=' + release.prepare(os.environ.get('TARGET_REF', ''), os.environ.get('DRY_RUN') == 'true'))
    elif mode == 'allowed':
        print('allowed=' + str(release.allowed()).lower())
    elif mode == 'checksums':
        source = run('git', 'rev-parse', 'HEAD').strip()
        paths = inventory(release.version, source)
        Path('dist/SHA256SUMS.txt').write_text(integrity.sha256(paths[0]) + '  ' + paths[0].name + '\n')
    elif mode == 'publish':
        release.publish(run('git', 'rev-parse', 'HEAD').strip())
    else: raise ValueError('未知发行命令')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, IndexError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        sys.exit('发行恢复失败：' + str(error))
