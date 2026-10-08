#!/usr/bin/env python3
# coding: utf-8
"""按发布通道摘取累计说明，并列出与上一个稳定版相比改动的插件包。"""
import argparse
import json
import pathlib
import re
import subprocess


def changes(text, version):
    base = version.split('-', 1)[0]
    sections = re.split(r'^##\s+', text, flags=re.M)[1:]
    wanted = ('未发布', 'Unreleased', base) if '-' in version else (base,)
    for section in sections:
        heading, _, body = section.partition('\n')
        title = re.split(r'[（(]', heading, maxsplit=1)[0].strip()
        if title in wanted:
            return body.strip()
    raise ValueError(f'CHANGELOG.md 缺少 {version} 的说明')


def plugin_changes(index, changed_paths):
    folders = {path.split('/')[1] for path in changed_paths if path.startswith('PluginBundles/') and len(path.split('/')) > 2}
    result = []
    for plugin in index['plugins']:
        folder = plugin['bundle'].removesuffix('.bundle')
        if folder not in folders and folder.removeprefix('Pop') not in folders:
            continue
        meta = plugin.get('meta', {})
        names = meta.get('name', {})
        name = names.get('zh-Hans', plugin['id']) if isinstance(names, dict) else names
        result.append(f"- {name}（{plugin['id']}）：{meta.get('version', index['version'])}")
    return sorted(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--previous', default='')
    parser.add_argument('--index', required=True)
    args = parser.parse_args()
    index = json.loads(pathlib.Path(args.index).read_text())
    if args.previous:
        paths = subprocess.check_output(['git', 'diff', '--name-only', args.previous, 'HEAD', '--', 'PluginBundles'], text=True).splitlines()
    else:
        paths = subprocess.check_output(['git', 'ls-files', 'PluginBundles'], text=True).splitlines()
    print(changes(pathlib.Path('CHANGELOG.md').read_text(), args.version))
    print('\n### 本版改动的插件包\n')
    plugins = plugin_changes(index, paths)
    print('\n'.join(plugins) if plugins else '本版没有插件包源码改动；插件包随 Pop 重新构建，以匹配本版构建标识。')


if __name__ == '__main__':
    main()
