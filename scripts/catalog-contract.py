#!/usr/bin/env python3
"""校验原生目录观察快照的结构并合并两语言；ICU与闭包行为不在Python中近似执行。"""
import argparse
import copy
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


def load_snapshot(path):
    paths = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    candidates = []
    for file in paths:
        if file.stat().st_size > 10 * 1024 * 1024:
            continue
        try:
            value = json.loads(file.read_bytes())
        except (ValueError, UnicodeError):
            continue
        if type(value) is dict and {"packages", "hostFunctions", "language"} <= value.keys():
            candidates.append(value)
    require(len(candidates) == 1, "附件中必须恰好有一个完整原生快照")
    return candidates[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zh", type=Path, required=True)
    parser.add_argument("--en", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = merge(load_snapshot(args.zh), load_snapshot(args.en))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"结构已核验：{len(result['packages'])}包；ICU由原生目标检查，custom闭包语义未声明等价")


if __name__ == "__main__":
    main()
