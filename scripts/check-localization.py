#!/usr/bin/env python3
"""检查界面文字的翻译。

Pop 的界面文字以中文原文作为 key（开发语言是简体中文），英文翻译在 en.lproj 里。
这个脚本检查：

1. zh-Hans 和 en 两份 .strings 的 key 完全一样，没有重复的 key、没有空的翻译；
2. 同一个 key 两种语言里的占位符（%@、%lld……）一致；
3. 给了 --stringsdata 时（编译时 SWIFT_EMIT_LOC_STRINGS=YES 生成的 .stringsdata 文件所在的目录），
   代码里用到的每一个带中文的 key 都有翻译。

单独发布的插件包把翻译放在自己的文件夹里（PluginBundles/<文件夹>/en.lproj、zh-Hans.lproj 的 Localizable.strings），
代码里用 bundle: 查自己的翻译。这些插件包的两份翻译也照上面检查，它们代码里用到的 key 查它自己的翻译；
代码里直接写中文、又没带 bundle: 的界面文字（Text("中文")、Button("中文")、String(localized: "中文") 这些）会去 Pop 里查，
查不到就显示中文，也报出来。

用法：
  scripts/check-localization.py                          只检查两份翻译文件
  scripts/check-localization.py --stringsdata <目录>     再检查代码里用到的 key
  scripts/check-localization.py --stringsdata <目录> --list-missing   把缺的 key 按 .strings 的格式列出来
  scripts/check-localization.py --sync-zh-hans           按 en 的 Localizable.strings 重写 zh-Hans 的那份（译文就是 key）

加新的界面文字：在 en.lproj/Localizable.strings 里加一行 "中文原文" = "English";，再跑一次 --sync-zh-hans
（单独发布的插件包加在它自己文件夹里的 en.lproj/Localizable.strings）。
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Pop", "Resources")
PLUGINS = os.path.join(ROOT, "PluginBundles")
LANGUAGES = ["zh-Hans", "en"]
TABLES = ["Localizable", "InfoPlist"]
HAN = re.compile(r"[\u3400-\u9fff]")
FORMAT = re.compile(r"%(?:(\d+)\$)?[-+0#]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfeEgGcCsSp%])")
HAN_RUN = re.compile(r"[\u3400-\u9fff]+")


class StringsError(Exception):
    pass


def unescape(s, path, line):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\":
            i += 1
            if i >= len(s):
                raise StringsError(f"{path}:{line}: 行尾有多余的反斜杠")
            e = s[i]
            if e == "n":
                out.append("\n")
            elif e == "t":
                out.append("\t")
            elif e == "r":
                out.append("\r")
            elif e in "\"\\'":
                out.append(e)
            elif e == "U" or e == "u":
                out.append(chr(int(s[i + 1:i + 5], 16)))
                i += 4
            else:
                raise StringsError(f"{path}:{line}: 不认识的转义 \\{e}")
        else:
            out.append(c)
        i += 1
    return "".join(out)


def parse_strings(path):
    """解析 .strings 文件，返回 [(key, value, 行号)]"""
    text = open(path, encoding="utf-8").read()
    # 去掉注释（不在字符串里的 /* */ 和 //）
    entries = []
    i = 0
    n = len(text)
    token = re.compile(r'"((?:[^"\\]|\\.)*)"', re.S)
    while i < n:
        c = text[i]
        if c.isspace():
            i += 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                raise StringsError(f"{path}: 注释没有结束")
            i = j + 2
            continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        line = text.count("\n", 0, i) + 1
        m = re.compile(r'"((?:[^"\\\n]|\\.)*)"\s*=\s*"((?:[^"\\\n]|\\.)*)"\s*;').match(text, i)
        if not m:
            raise StringsError(f"{path}:{line}: 格式不对，应该是 \"key\" = \"value\";")
        entries.append((unescape(m.group(1), path, line), unescape(m.group(2), path, line), line))
        i = m.end()
    return entries


def escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def placeholders(s):
    """占位符的列表（按位置编号排序），忽略 %%"""
    result = []
    index = 0
    for m in FORMAT.finditer(s):
        if m.group(3) == "%":
            continue
        index += 1
        position = int(m.group(1)) if m.group(1) else index
        kind = m.group(3)
        # %lld 和 %ld、%d 都是整数；%lf 和 %f 都是浮点数
        if kind in "dDiuUxXoO":
            kind = "int"
        elif kind in "feEgG":
            kind = "float"
        result.append((position, kind))
    return sorted(result)


def plugin_folders():
    """自己带翻译的插件包：文件夹名 → 放翻译的文件夹（PluginBundles/<文件夹>）"""
    result = {}
    if not os.path.isdir(PLUGINS):
        return result
    for name in sorted(os.listdir(PLUGINS)):
        folder = os.path.join(PLUGINS, name)
        if os.path.isfile(os.path.join(folder, "en.lproj", "Localizable.strings")):
            result[name] = folder
    return result


# 单独发布的插件包里，这些写法的中文会去 Pop 的翻译里查：要带 bundle:（Text、String(localized:)），
# 或者换成带 label 的写法（Button { } label: { Text("中文", bundle: …) }）
UNBUNDLED = re.compile(
    r'(?<![\w.])(?:Text|Button|Toggle|Label|Picker|Menu|Section|TextField|SecureField|Stepper|DatePicker|Link|LabeledContent|'
    r'ProgressView|ContentUnavailableView|GroupBox|DisclosureGroup)\(\s*"[^"\n]*[\u3400-\u9fff]'
    r'|\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle|alert|confirmationDialog)\(\s*"[^"\n]*[\u3400-\u9fff]'
    r'|String\(localized:\s*"(?:[^"\\\n]|\\.)*"(?!\s*,\s*(?:table:\s*[^,]+,\s*)?bundle:)')


def unbundled_strings(folder):
    """单独发布的插件包里没带 bundle: 的界面文字：[(文件:行, 那一行)]"""
    found = []
    for dirpath, _, files in os.walk(folder):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            for number, line in enumerate(open(path, encoding="utf-8"), 1):
                code = line.split("//")[0] if "//" in line and '"' not in line.split("//")[0] else line
                for m in UNBUNDLED.finditer(code):
                    rest = code[m.start():]
                    # Text("中文", bundle: …)、String(localized: "中文", bundle: …) 是对的
                    if rest.startswith("Text(") and re.match(r'Text\(\s*"(?:[^"\\]|\\.)*"\s*,\s*(?:tableName:\s*[^,]+,\s*)?bundle:', rest):
                        continue
                    if not HAN.search(m.group(0)):
                        continue
                    found.append((f"{os.path.relpath(path, ROOT)}:{number}", line.strip()))
    return found


def owner(source, plugins):
    """这个源文件用谁的翻译：自己带翻译的插件包的文件夹名，或者 None（Pop 的）"""
    parts = source.replace("\\", "/").split("/")
    for i, part in enumerate(parts[:-1]):
        if part == "PluginBundles" and i + 1 < len(parts) - 1 and parts[i + 1] in plugins:
            return parts[i + 1]
    return None


def load_stringsdata(directory):
    """编译器抽出来的 key：{key: [来源文件（完整路径）]}"""
    keys = {}
    for dirpath, _, files in os.walk(directory):
        for name in files:
            if not name.endswith(".stringsdata"):
                continue
            try:
                data = json.load(open(os.path.join(dirpath, name), encoding="utf-8"))
            except (ValueError, OSError):
                continue
            source = data.get("source", name)
            for table, items in data.get("tables", {}).items():
                if table != "Localizable":
                    continue
                for item in items:
                    key = item.get("key")
                    if key is not None:
                        keys.setdefault(key, set()).add(source)
    return keys


def sync_zh_hans():
    """zh-Hans 的译文就是 key 本身；保留 en 文件里的注释和顺序。自己带翻译的插件包也一样"""
    sync_pair(os.path.join(RESOURCES, "en.lproj", "Localizable.strings"), os.path.join(RESOURCES, "zh-Hans.lproj", "Localizable.strings"))
    for folder in plugin_folders().values():
        zh_folder = os.path.join(folder, "zh-Hans.lproj")
        os.makedirs(zh_folder, exist_ok=True)
        sync_pair(os.path.join(folder, "en.lproj", "Localizable.strings"), os.path.join(zh_folder, "Localizable.strings"))


def sync_pair(en_path, zh_path):
    line_re = re.compile(r'^(\s*)"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;(.*)$')
    out = []
    for line in open(en_path, encoding="utf-8").read().split("\n"):
        m = line_re.match(line)
        if m:
            out.append(f'{m.group(1)}"{m.group(2)}" = "{m.group(2)}";{m.group(4)}')
        else:
            out.append(line)
    open(zh_path, "w", encoding="utf-8").write("\n".join(out))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stringsdata", help="编译时生成的 .stringsdata 文件所在的目录")
    parser.add_argument("--list-missing", action="store_true", help="列出代码里用到、但还没有翻译的 key")
    parser.add_argument("--sync-zh-hans", action="store_true", help="按 en 的 Localizable.strings 重写 zh-Hans 的那份")
    args = parser.parse_args()

    if args.sync_zh_hans:
        sync_zh_hans()

    errors = []
    tables = {}
    for table in TABLES:
        tables[table] = check_tables(RESOURCES, table, table, errors)
    plugins = plugin_folders()
    plugin_tables = {name: check_tables(folder, "Localizable", f"{name}/Localizable", errors).get("en", {})
                     for name, folder in plugins.items()}
    for name, folder in plugins.items():
        for place, line in unbundled_strings(folder):
            errors.append(f"{place}: 单独发布的插件包里的界面文字要查它自己的翻译（带 bundle:）：{line}")

    localizable = tables.get("Localizable", {}).get("en", {})
    missing = []
    if args.stringsdata:
        used = load_stringsdata(args.stringsdata)
        if not used:
            errors.append(f"{args.stringsdata} 里没有找到 .stringsdata 文件（编译时要打开 SWIFT_EMIT_LOC_STRINGS）")
        used_by_pop = set()
        for key in sorted(used):
            # 不带中文的 key（比如「JSON」「⌘C」）没有翻译时原样显示，不用管
            lacking = set()
            for source in used[key]:
                plugin = owner(source, plugins)
                if plugin is None:
                    used_by_pop.add(key)
                if HAN.search(key) and key not in (localizable if plugin is None else plugin_tables[plugin]):
                    lacking.add(f"{plugin}/" if plugin else "")
            if lacking:
                missing.append((key, sorted({os.path.basename(s) for s in used[key]}), sorted(lacking)))
        unused = sorted(k for k in localizable if k not in used_by_pop)
        print(f"代码里用到 {len(used)} 个 key，带中文的 {sum(1 for k in used if HAN.search(k))} 个；"
              f"翻译文件里 {len(localizable)} 个，其中 {len(unused)} 个代码里没直接用到（可能是运行时查的）")
        for key, sources, where in missing:
            place = "、".join(f"{w}en.lproj" if w else "Pop" for w in where)
            errors.append(f"缺少翻译（{', '.join(sources)}，要加在 {place}）：{key!r}")

    if args.list_missing and missing:
        print("---- 缺少的 key ----")
        for key, sources, _ in missing:
            print(f"/* {', '.join(sources)} */")
            print(f'"{escape(key)}" = "";')
        print("---- 以上 ----")

    if errors:
        for e in errors:
            print(f"::error::{e}" if os.environ.get("GITHUB_ACTIONS") else e)
        print(f"翻译检查没通过：{len(errors)} 个问题")
        return 1
    print(f"翻译检查通过：{len(localizable)} 条界面文字" + (f"，另有 {len(plugins)} 个插件包自带翻译" if plugins else ""))
    return 0


def check_tables(resources, table, label, errors):
    """检查一张表（zh-Hans 和 en 两份）：key 一样、不重复、不空、占位符一致、英文里没有多出来的中文。返回 {语言: {key: 译文}}"""
    per_language = {}
    for language in LANGUAGES:
        path = os.path.join(resources, f"{language}.lproj", f"{table}.strings")
        if not os.path.exists(path):
            errors.append(f"缺少 {os.path.relpath(path, ROOT)}")
            continue
        try:
            entries = parse_strings(path)
        except StringsError as e:
            errors.append(str(e))
            continue
        values = {}
        for key, value, line in entries:
            if key in values:
                errors.append(f"{os.path.relpath(path, ROOT)}:{line}: key 重复：{key!r}")
            if not value.strip():
                errors.append(f"{os.path.relpath(path, ROOT)}:{line}: 翻译是空的：{key!r}")
            values[key] = value
        per_language[language] = values
    if len(per_language) == len(LANGUAGES):
        zh, en = per_language["zh-Hans"], per_language["en"]
        for key in sorted(set(zh) - set(en)):
            errors.append(f"{label}: en 里缺少 {key!r}")
        for key in sorted(set(en) - set(zh)):
            errors.append(f"{label}: zh-Hans 里缺少 {key!r}")
        for key in sorted(set(zh) & set(en)):
            if placeholders(zh[key]) != placeholders(en[key]):
                errors.append(f"{label}: 占位符不一致 {key!r}：zh-Hans {zh[key]!r}，en {en[key]!r}")
            if table == "Localizable" and placeholders(key) != placeholders(en[key]):
                errors.append(f"{label}: 译文和 key 的占位符不一致 {key!r}：{en[key]!r}")
            # 英文里可以原样引用 key 里的中文（比如文件名「Pop 收集箱.md」、要识别的中文说法），别的中文不行
            if any(run not in key for run in HAN_RUN.findall(en[key])):
                errors.append(f"{label}: 英文翻译里还有中文 {key!r}：{en[key]!r}")
    return per_language


if __name__ == "__main__":
    sys.exit(main())
