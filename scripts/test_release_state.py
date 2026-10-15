import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('release_state', Path(__file__).with_name('release-state.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
SOURCE = 'a' * 40
VERSION = '0.70.2'


class FakeRelease(m.Release):
    def __init__(self):
        super().__init__(VERSION)
        self.state = None
        self.tag_sha = None
        self.mutations = []
        self.allowed_results = []
        self.upload_fails = False
        self.drift = False

    def find(self): return copy.deepcopy(self.state)
    def tag_commit(self): return self.tag_sha
    def validated(self, source):
        if source != SOURCE: raise ValueError('unvalidated source')
    def allowed(self): return self.allowed_results.pop(0) if self.allowed_results else True
    def releases(self): return [copy.deepcopy(self.state)] if self.state else []
    def api(self, path, payload=None):
        if payload is not None:
            self.mutations.append((path, payload))
            if path == 'git/refs':
                self.tag_sha = payload['sha']
                return dict(ref=payload['ref'], object={'sha': self.tag_sha})
            if path == 'releases':
                self.state = dict(payload, id=1, assets=[])
            else: self.state.update(payload)
        if path.startswith('commits/'): return {'sha': SOURCE}
        return copy.deepcopy(self.state)
    def command(self, args, **kwargs):
        if args[:3] == ['gh', 'release', 'upload']:
            paths = args[4:args.index('--repo')]
            for index, name in enumerate(paths):
                file = Path(name)
                shutil.copyfile(file, Path('remote') / file.name)
                self.state['assets'] = [v for v in self.state['assets'] if v['name'] != file.name] + [dict(
                    name=file.name, size=file.stat().st_size, state='uploaded',
                    digest='sha256:' + m.integrity.sha256(file))]
                if self.upload_fails and index == 0: raise subprocess.CalledProcessError(1, args)
            if self.drift: self.state['target_commitish'] = 'b' * 40
        elif args[:3] == ['gh', 'release', 'download']:
            name = args[args.index('--pattern') + 1]
            directory = args[args.index('--dir') + 1]
            shutil.copyfile(Path('remote') / name, Path(directory) / name)
        else: raise AssertionError(args)
        return subprocess.CompletedProcess(args, 0)


class ReleaseStateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        old = Path.cwd()
        os.chdir(self.tmp.name)
        self.addCleanup(os.chdir, old)
        self.env = patch.dict(os.environ, GITHUB_REPOSITORY='whrss9527/pop', PRERELEASE='false', DRY_RUN='false')
        self.env.start(); self.addCleanup(self.env.stop)
        Path('remote').mkdir()
        Path('dist/plugins').mkdir(parents=True)
        Path('project.yml').write_text('        POP_PLUGIN_ID: fixture\n')
        Path('notes.md').write_text('fixture release notes')
        self.app = Path('dist/Pop-0.70.2.zip')
        self.plugin = Path('dist/plugins/plugin-fixture.zip')
        self.index = Path('dist/plugins/plugins-0.70.2.json')
        build = VERSION + '+' + SOURCE[:12]
        self.zip(self.app, 'Pop.app', dict(CFBundleShortVersionString=VERSION, PopBuildID=build))
        self.zip(self.plugin, 'Fixture.bundle', dict(PopBuildID=build, PopPluginID='fixture'))
        self.entry = dict(id='fixture', bundle='Fixture.bundle', file=self.plugin.name,
                          size=self.plugin.stat().st_size, sha256=m.integrity.sha256(self.plugin))
        self.index.write_text(json.dumps(dict(format=1, version=VERSION, build=build, plugins=[self.entry])))
        self.sums()

    @staticmethod
    def zip(path, bundle, info):
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(bundle + '/Contents/Info.plist', plistlib.dumps(info))

    def sums(self):
        Path('dist/SHA256SUMS.txt').write_text(m.integrity.sha256(self.app) + '  ' + self.app.name + '\n')

    def publish(self, release):
        with patch.object(m.subprocess, 'run', side_effect=release.command): release.publish(SOURCE)

    def test_upload_failure_stays_hidden_and_retry_checks_every_remote_asset(self):
        release = FakeRelease(); release.upload_fails = True
        with self.assertRaises(subprocess.CalledProcessError): self.publish(release)
        self.assertTrue(release.state['draft'])
        self.assertEqual(len(release.state['assets']), 1)
        release.upload_fails = False
        self.assertEqual(release.prepare(SOURCE), SOURCE)
        self.publish(release)
        self.assertFalse(release.state['draft'])
        self.assertEqual({v['name'] for v in release.state['assets']},
                         {self.app.name, self.plugin.name, self.index.name, 'SHA256SUMS.txt'})
        self.assertEqual(sum(path == 'releases/1' for path, _ in release.mutations), 1)

    def test_published_release_is_never_modified(self):
        release = FakeRelease()
        self.publish(release)
        before = copy.deepcopy(release.state)
        mutations = list(release.mutations)
        with self.assertRaises(ValueError): release.prepare(SOURCE)
        with self.assertRaises(ValueError): self.publish(release)
        self.assertEqual(release.state, before)
        self.assertEqual(release.mutations, mutations)

    def test_source_drift_stops_before_publication(self):
        release = FakeRelease(); release.drift = True
        with self.assertRaises(ValueError): self.publish(release)
        self.assertTrue(release.state['draft'])
        self.assertFalse(any(path == 'releases/1' for path, _ in release.mutations))

    def test_daily_cap_recheck_leaves_complete_draft_for_next_day(self):
        release = FakeRelease(); release.allowed_results = [True, False]
        self.publish(release)
        self.assertTrue(release.state['draft'])
        self.assertEqual(len(release.state['assets']), 4)
        self.publish(release)
        self.assertFalse(release.state['draft'])

    def test_unexpected_draft_asset_stops_publication_without_deleting_it(self):
        release = FakeRelease()
        release.state = dict(id=1, tag_name='v'+VERSION, target_commitish=SOURCE, draft=True, prerelease=False,
                             assets=[dict(name='operator-note.txt', size=1, state='uploaded', digest='sha256:'+'0'*64)])
        with self.assertRaises(ValueError): self.publish(release)
        self.assertTrue(release.state['draft'])
        self.assertIn('operator-note.txt', {v['name'] for v in release.state['assets']})

    def test_local_plugin_inventory_rejects_missing_hash_abi_and_source_changes(self):
        original = self.index.read_text()
        for mode in ['missing', 'duplicate', 'hash', 'build']:
            with self.subTest(mode=mode):
                index = json.loads(original)
                if mode == 'missing': index['plugins'] = []
                elif mode == 'duplicate': index['plugins'] *= 2
                elif mode == 'hash': index['plugins'][0]['sha256'] = '0'*64
                else: index['build'] = 'other'
                self.index.write_text(json.dumps(index))
                with self.assertRaises(ValueError): m.inventory(VERSION, SOURCE)
        self.index.write_text(original)
        with self.assertRaises(ValueError): m.inventory(VERSION, 'b'*40)
        self.zip(self.plugin, 'Fixture.bundle', dict(PopBuildID='other', PopPluginID='fixture'))
        index = json.loads(original); index['plugins'][0].update(size=self.plugin.stat().st_size, sha256=m.integrity.sha256(self.plugin))
        self.index.write_text(json.dumps(index))
        with self.assertRaises(ValueError): m.inventory(VERSION, SOURCE)

    def test_exact_four_ci_gates_and_source_ancestry_are_required(self):
        release = m.Release(VERSION)
        runs = [dict(id=4, run_number=5, head_sha=SOURCE, head_branch='main', event='push')]
        gates = [dict(name=name, status='completed', conclusion='success') for name in m.GATES]
        with patch.object(release, 'api', return_value={'status':'ahead'}), patch.object(release, 'pages', side_effect=[runs,gates]):
            release.validated(SOURCE)
        for broken in [gates[:-1], [dict(v, conclusion='failure') for v in gates]]:
            with patch.object(release, 'api', return_value={'status':'identical'}), patch.object(release, 'pages', side_effect=[runs,broken]):
                with self.assertRaises(ValueError): release.validated(SOURCE)
        with patch.object(release, 'api', return_value={'status':'diverged'}):
            with self.assertRaises(ValueError): release.validated(SOURCE)

    def test_concatenated_pagination_does_not_stop_at_short_pages(self):
        values = list(m.documents('[]\n[{"id":1}]\n[]\n[{"id":2}]'))
        self.assertEqual([v['id'] for page in values for v in page], [1,2])

    def test_metadata_checksum_and_tag_drift_fail_closed(self):
        release = FakeRelease()
        self.publish(release)
        with patch.object(release, 'tag_commit', return_value='b'*40):
            with self.assertRaises(ValueError): release.bound(release.state, SOURCE, require_tag=True)
        release.state['draft'] = True
        release.state['prerelease'] = True
        with self.assertRaises(ValueError): release.prepare(SOURCE)
        release.state['prerelease'] = False
        Path('dist/SHA256SUMS.txt').write_text('0'*64 + '  ' + self.app.name + '\n')
        previous = list(release.mutations)
        with self.assertRaises(ValueError): self.publish(release)
        self.assertEqual(release.mutations, previous)

    def test_remote_digest_corruption_stays_draft(self):
        release = FakeRelease()
        command = release.command
        def corrupt(args, **kwargs):
            result = command(args, **kwargs)
            if args[:3] == ['gh', 'release', 'upload']:
                release.state['assets'][0]['digest'] = 'sha256:' + '0'*64
            return result
        with patch.object(m.subprocess, 'run', side_effect=corrupt):
            with self.assertRaises(ValueError): release.publish(SOURCE)
        self.assertTrue(release.state['draft'])

    def test_external_publication_before_upload_stops_asset_writes(self):
        release = FakeRelease()
        api = release.api
        def publish_elsewhere(path, payload=None):
            if path == 'releases/1' and payload is None: release.state['draft'] = False
            return api(path, payload)
        with patch.object(release, 'api', side_effect=publish_elsewhere):
            with self.assertRaises(ValueError): self.publish(release)
        self.assertEqual(list(Path('remote').iterdir()), [])

    def test_missing_api_digests_download_and_check_actual_asset_bytes(self):
        release = FakeRelease()
        command = release.command
        def legacy_api(args, **kwargs):
            result = command(args, **kwargs)
            if args[:3] == ['gh', 'release', 'upload']:
                for asset in release.state['assets']: asset.pop('digest')
            return result
        with patch.object(m.subprocess, 'run', side_effect=legacy_api): release.publish(SOURCE)
        self.assertFalse(release.state['draft'])
