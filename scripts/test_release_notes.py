# coding: utf-8
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release_notes', Path(__file__).with_name('release-notes.py'))
notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notes)


class ReleaseNotesTests(unittest.TestCase):
    def test_beta_uses_accumulated_unreleased_notes(self):
        self.assertEqual(notes.changes('## 未发布\n- new\n## 1.0.0（date）\n- old', '1.1.0-beta.2'), '- new')

    def test_promoted_beta_and_stable_use_matching_section(self):
        text = '## 1.1.0（date）\n- new\n## 1.0.0\n- old'
        self.assertEqual(notes.changes(text, '1.1.0-beta.2'), '- new')
        self.assertEqual(notes.changes(text, '1.0.0'), '- old')
        with self.assertRaises(ValueError):
            notes.changes(text, '1.2.0')

    def test_lists_only_changed_plugins_with_independent_versions(self):
        index = {'version': '1.1.0', 'plugins': [
            {'id': 'zip', 'bundle': 'PopZip.bundle'},
            {'id': 'rss', 'bundle': 'PopRSS.bundle', 'meta': {'name': {'zh-Hans': '订阅'}, 'version': '0.3.0'}},
            {'id': 'other', 'bundle': 'PopOther.bundle'}]}
        result = notes.plugin_changes(index, ['PluginBundles/Zip/Zip.swift', 'PluginBundles/RSS/plugin.json', 'docs/guide.md'])
        self.assertEqual(result, ['- zip（zip）：1.1.0', '- 订阅（rss）：0.3.0'])

    def test_reads_comparison_tags_created_after_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            origin = root / 'origin.git'
            checkout = root / 'checkout'

            def git(*arguments):
                return subprocess.check_output(['git', '-c', 'commit.gpgsign=false', *arguments],
                                               cwd=root, text=True, stderr=subprocess.PIPE).strip()

            git('init', '--bare', '--initial-branch=main', str(origin))
            git('clone', str(origin), str(checkout))
            git('-C', str(checkout), 'config', 'user.name', 'Pop Tests')
            git('-C', str(checkout), 'config', 'user.email', 'tests@example.invalid')
            plugin = checkout / 'PluginBundles' / 'Zip' / 'Zip.swift'
            plugin.parent.mkdir(parents=True)
            plugin.write_text('let version = 1\n')
            changelog = checkout / 'CHANGELOG.md'
            changelog.write_text('## 1.0.0\n- old\n')
            git('-C', str(checkout), 'add', '.')
            git('-C', str(checkout), 'commit', '-m', 'Initial fixture')
            previous = git('-C', str(checkout), 'rev-parse', 'HEAD')
            git('-C', str(checkout), 'push', 'origin', 'main')
            plugin.write_text('let version = 2\n')
            changelog.write_text('## 未发布\n- new\n## 1.0.0\n- old\n')
            git('-C', str(checkout), 'add', '.')
            git('-C', str(checkout), 'commit', '-m', 'Update fixture')
            current = git('-C', str(checkout), 'rev-parse', 'HEAD')
            git('-C', str(checkout), 'push', 'origin', 'main')
            git('-C', str(origin), 'tag', 'v1.0.0', previous)
            git('-C', str(origin), 'tag', 'v1.1.0', current)
            self.assertEqual(git('-C', str(checkout), 'tag', '--list'), '')
            index = checkout / 'plugins.json'
            index.write_text(json.dumps({'version': '1.1.0', 'plugins': [{'id': 'zip', 'bundle': 'PopZip.bundle'}]}))

            for tag, expected in [('v1.0.0', '- zip（zip）：1.1.0'),
                                  ('v1.1.0', '本版没有插件包源码改动'),
                                  ('v1.1.0', '本版没有插件包源码改动')]:
                with self.subTest(tag=tag):
                    result = subprocess.run([sys.executable, str(Path(notes.__file__).resolve()),
                                             '--version', '1.1.0-beta.2', '--previous', tag,
                                             '--index', str(index)], cwd=checkout, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('- new', result.stdout)
                    self.assertIn(expected, result.stdout)
