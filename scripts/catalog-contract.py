#!/usr/bin/env python3
"""校验原生目录观察快照的结构并合并两语言；ICU与闭包行为不在Python中近似执行。"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

CATEGORIES = {"text", "ai", "convert", "developer", "screen", "recording", "files", "other"}
KINDS = {"text", "chineseText", "foreignText", "url", "email", "math", "timestamp", "json",
         "files", "image", "word", "color", "number", "dateTime", "imageFile", "measurement"}
CHECKS = {"colorPair", "extractable", "characters", "lineList", "yamlOrJSON", "xml", "sql",
          "base64Image", "twoDates", "folder", "twoFolders", "markdownHeadings", "idNumber"}
CUSTOM = {"appInfoBundle", "appBundle", "twoImageFiles", "twoTextFiles", "textFiles", "mediaInfoFiles",
          "subtitleFiles", "similarPhotos", "chart", "cron", "numberList", "dateMention"}
FUNCTION_FIELDS = {"id", "name", "summary", "symbol", "category", "accepts", "pattern", "minLength",
                   "maxLength", "source", "hidesOverlay", "optionalContent", "check"}
PACKAGE_FIELDS = {"id", "bundleName", "name", "summary", "symbol", "category", "independentVersion",
                  "functions", "defaultsKeys", "keychainAccounts", "dataFolders"}
TOP_FIELDS = {"schemaVersion", "language", "appVersion", "buildID", "packages", "hostFunctions", "displayOrder"}
METADATA_FIELDS = {"source", "system", "xcode", "scope"}
EVIDENCE_ROLES = {"zh", "en", "metadata", "contract"}


def require(value, message):
    if not value:
        raise ValueError(message)


def fields(value, expected):
    require(type(value) is dict and set(value) == expected, "字段缺失、未知或对象类型无效")


def text(value):
    require(type(value) is str and bool(value.strip()) and "\0" not in value, "字符串或本地化为空/无效")


def identifier(value):
    text(value)
    require(re.fullmatch(r"[A-Za-z][A-Za-z0-9._:-]*", value) is not None, "标识符无效")


def strings(value):
    require(type(value) is list, "应为字符串数组")
    for item in value:
        text(item)
    require(len(value) == len(set(value)), "字符串数组重复")


def relative_path(value):
    text(value)
    require(not value.startswith("/") and "\\" not in value and "\0" not in value
            and all(part not in ("", ".", "..") for part in value.split("/")), "数据目录必须是安全相对路径")


def function(value, seen):
    fields(value, FUNCTION_FIELDS)
    identifier(value["id"])
    require(value["id"] not in seen, "功能ID重复或归属不唯一")
    seen.add(value["id"])
    for name in ("name", "summary", "symbol"):
        text(value[name])
    require(type(value["category"]) is str and value["category"] in CATEGORIES, "未知分类")
    strings(value["accepts"])
    require(set(value["accepts"]) <= KINDS, "未知内容类型")
    require(value["source"] == "builtin", "原生契约不能冒充用户插件")
    for name in ("hidesOverlay", "optionalContent"):
        require(type(value[name]) is bool, "标志必须是Bool")
    for name in ("minLength", "maxLength"):
        v = value[name]
        require(v is None or (type(v) is int and 0 <= v <= 2**63 - 1), "长度必须是非负Int或null")
    if value["minLength"] is not None and value["maxLength"] is not None:
        require(value["minLength"] <= value["maxLength"], "长度范围倒置")
    require(value["pattern"] is None or type(value["pattern"]) is str, "pattern必须是String或null")
    # NSRegularExpression/ICU由原生导出目标检查；Python re不是相同方言。
    check = value["check"]
    if check is not None:
        require(type(check) is dict and type(check.get("kind")) is str, "内容检查对象无效")
        if check["kind"] == "custom":
            fields(check, {"kind", "id"})
            require(type(check["id"]) is str and check["id"] in CUSTOM, "未知custom检查，不能假设可执行或返回true")
        else:
            fields(check, {"kind"})
            require(check["kind"] in CHECKS, "未知内容检查")


def validate_snapshot(value):
    fields(value, TOP_FIELDS)
    require(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1, "未知schema版本")
    require(value["language"] in ("zh-Hans", "en"), "未知快照语言")
    text(value["appVersion"])
    text(value["buildID"])
    require(type(value["packages"]) is list and value["packages"], "缺少插件包")
    require(type(value["hostFunctions"]) is list and value["hostFunctions"], "缺少主程序功能")
    seen, packages, bundles = set(), set(), set()
    for package in value["packages"]:
        fields(package, PACKAGE_FIELDS)
        identifier(package["id"])
        require(package["id"] not in packages, "包ID重复")
        packages.add(package["id"])
        bundle = package["bundleName"]
        require(type(bundle) is str and re.fullmatch(r"Pop[A-Za-z0-9_]+", bundle), "包名不能包含路径")
        require(bundle not in bundles, "包名重复")
        bundles.add(bundle)
        for name in ("name", "summary", "symbol"):
            text(package[name])
        require(type(package["category"]) is str and package["category"] in CATEGORIES, "未知包分类")
        if package["independentVersion"] is not None:
            text(package["independentVersion"])
        for name in ("defaultsKeys", "keychainAccounts", "dataFolders"):
            strings(package[name])
        for path in package["dataFolders"]:
            relative_path(path)
        require(type(package["functions"]) is list and package["functions"], "包没有功能")
        for entry in package["functions"]:
            function(entry, seen)
            require(entry["category"] == package["category"], "包内功能分类不符")
    for entry in value["hostFunctions"]:
        function(entry, seen)
    strings(value["displayOrder"])
    require(set(value["displayOrder"]) <= seen, "展示顺序含未知功能")
    return value


def without_text(value):
    result = copy.deepcopy(value)
    result.pop("language")
    for package in result["packages"]:
        package.pop("name")
        package.pop("summary")
    for entry in [f for p in result["packages"] for f in p["functions"]] + result["hostFunctions"]:
        entry.pop("name")
        entry.pop("summary")
    return result


def merge(chinese, english):
    validate_snapshot(chinese)
    validate_snapshot(english)
    require(chinese["language"] == "zh-Hans" and english["language"] == "en", "必须提供不同的两语言快照")
    require(without_text(chinese) == without_text(english), "两语言的结构、构建或约束不同")
    result = copy.deepcopy(chinese)
    result.pop("language")
    result["languages"] = ["zh-Hans", "en"]
    pairs = list(zip(result["packages"], english["packages"]))
    pairs += list(zip(result["hostFunctions"], english["hostFunctions"]))
    pairs += [(a, b) for p, q in zip(result["packages"], english["packages"])
              for a, b in zip(p["functions"], q["functions"])]
    for a, b in pairs:
        for name in ("name", "summary"):
            a[name] = {"zh-Hans": a[name], "en": b[name]}
    return result


def snapshot_file(path, root=None):
    paths = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    candidates = []
    for file in paths:
        if root is not None:
            within_root(root, file)
        if file.stat().st_size > 10 * 1024 * 1024:
            continue
        try:
            value = json.loads(file.read_bytes())
        except (ValueError, UnicodeError):
            continue
        if type(value) is dict and {"packages", "hostFunctions", "language"} <= value.keys():
            candidates.append((file, value))
    require(len(candidates) == 1, "附件中必须恰好有一个完整原生快照")
    return candidates[0]


def load_snapshot(path):
    return snapshot_file(path)[1]


def source_sha(value):
    require(type(value) is str and re.fullmatch(r"[0-9a-f]{40}", value), "源码必须是完整Git SHA")


def within_root(root, path):
    resolved = path.resolve()
    require(resolved.is_relative_to(root) and resolved != root, "证据文件必须位于清单目录内")
    return resolved


def bound_merge(chinese, english, metadata, source):
    source_sha(source)
    fields(metadata, METADATA_FIELDS)
    for name in METADATA_FIELDS:
        text(metadata[name])
    require(metadata["source"] == source, "元数据源码与预期SHA不符")
    result = merge(chinese, english)
    require(result["buildID"] == source, "原生宿主/插件构建标识与源码SHA不符")
    return result


def verify_manifest(manifest, source):
    source_sha(source)
    root = manifest.parent.resolve()
    within_root(root, manifest)
    evidence = json.loads(manifest.read_bytes())
    fields(evidence, {"schemaVersion", "source", "files"})
    require(type(evidence["schemaVersion"]) is int and evidence["schemaVersion"] == 1, "未知证据版本")
    require(evidence["source"] == source, "证据清单源码与预期SHA不符")
    fields(evidence["files"], EVIDENCE_ROLES)
    paths, contents = set(), {}
    for role, entry in evidence["files"].items():
        fields(entry, {"path", "bytes", "sha256"})
        relative_path(entry["path"])
        path = within_root(root, root / entry["path"])
        require(path not in paths and path != manifest.resolve(), "证据路径重复或指向清单本身")
        paths.add(path)
        require(type(entry["bytes"]) is int and entry["bytes"] >= 0, "文件长度必须是非负Int")
        require(type(entry["sha256"]) is str and re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]), "SHA256无效")
        data = path.read_bytes()
        require(len(data) == entry["bytes"] and hashlib.sha256(data).hexdigest() == entry["sha256"],
                f"证据文件长度或SHA256不符：{role}")
        contents[role] = json.loads(data)
    result = bound_merge(contents["zh"], contents["en"], contents["metadata"], source)
    # JSON 比较保留 Bool/Int 差异，不能让 Python 的 False == 0 放过类型漂移。
    require(json.dumps(contents["contract"], sort_keys=True) == json.dumps(result, sort_keys=True),
            "合并目录与原始快照不符")
    return result


def export_contract(chinese, english, metadata, source, output, manifest):
    root = manifest.parent.resolve()
    root.mkdir(parents=True, exist_ok=True)
    for path in (chinese, english, metadata, output, manifest):
        within_root(root, path)
    zh_file, zh = snapshot_file(chinese, root)
    en_file, en = snapshot_file(english, root)
    result = bound_merge(zh, en, json.loads(metadata.read_bytes()), source)
    paths = {"zh": zh_file, "en": en_file, "metadata": metadata, "contract": output}
    resolved = [path.resolve() for path in paths.values()]
    require(len(set(resolved)) == len(resolved) and manifest.resolve() not in resolved,
            "输出不能覆盖原始快照、元数据或证据清单")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    files = {}
    for role, path in paths.items():
        data = path.read_bytes()
        files[role] = {"path": path.resolve().relative_to(root).as_posix(), "bytes": len(data),
                       "sha256": hashlib.sha256(data).hexdigest()}
    manifest.write_text(json.dumps({"schemaVersion": 1, "source": source, "files": files},
                                   ensure_ascii=False, indent=2) + "\n")
    return verify_manifest(manifest, source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export", help="校验源码绑定并生成目录与文件摘要清单")
    for name in ("zh", "en", "metadata", "output", "manifest"):
        export.add_argument("--" + name, type=Path, required=True)
    export.add_argument("--source", required=True)
    verify = commands.add_parser("verify", help="重新核验已保存的原始快照、元数据与目录")
    verify.add_argument("--manifest", type=Path, required=True)
    verify.add_argument("--source", required=True)
    args = parser.parse_args()
    if args.command == "export":
        result = export_contract(args.zh, args.en, args.metadata, args.source, args.output, args.manifest)
    else:
        result = verify_manifest(args.manifest, args.source)
    print(f"结构与源码/文件摘要已核验：{len(result['packages'])}包；ICU由原生目标检查，custom闭包语义未声明等价")


if __name__ == "__main__":
    main()
