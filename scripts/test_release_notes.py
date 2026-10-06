# coding: utf-8
import importlib.util
from pathlib import Path
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
