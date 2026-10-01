#!/usr/bin/env bash
# 把构建好、签好名的插件包打成发布用的压缩包，并写出插件包列表（Pop 装插件时从发布页下载它们）：
#   <输出目录>/plugin-<ID>.zip           每个插件包一个，里面是 PopXxx.bundle
#   <输出目录>/plugins-<版本号>.json     插件包列表：ID、文件名、SHA-256、下载大小、装好后的大小，以及构建标识
#   <输出目录>/plugins-notary.zip        所有插件包放在一起，提交公证用（不上传）
# 压缩包的文件名不能以 Pop 开头：已经装好的旧版 Pop 一键更新时，找的是发布页上「Pop 开头的 .zip」。
#
# 用法：scripts/package-plugins.sh <放着插件包的文件夹> <输出目录> <版本号>
set -euo pipefail

SRC="${1:?用法: scripts/package-plugins.sh <放着插件包的文件夹> <输出目录> <版本号>}"
OUT="${2:?用法: scripts/package-plugins.sh <放着插件包的文件夹> <输出目录> <版本号>}"
VERSION="${3:?用法: scripts/package-plugins.sh <放着插件包的文件夹> <输出目录> <版本号>}"
mkdir -p "$OUT"

python3 - "$SRC" "$OUT" "$VERSION" <<'PY'
import hashlib, json, os, plistlib, shutil, subprocess, sys, tempfile

src, out, version = sys.argv[1:4]

def tree_size(path):
    total = 0
    for folder, _, files in os.walk(path):
        for name in files:
            total += os.lstat(os.path.join(folder, name)).st_size
    return total

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

entries = []
builds = set()
bundles = []
for name in sorted(os.listdir(src)):
    bundle = os.path.join(src, name)
    plist = os.path.join(bundle, "Contents", "Info.plist")
    if not name.endswith(".bundle") or not os.path.isfile(plist):
        continue
    with open(plist, "rb") as f:
        info = plistlib.load(f)
    plugin_id = info.get("PopPluginID")
    if not plugin_id:
        continue
    builds.add(info.get("PopBuildID", ""))
    archive = f"plugin-{plugin_id}.zip"
    target = os.path.join(out, archive)
    if os.path.exists(target):
        os.remove(target)
    subprocess.run(["ditto", "-c", "-k", "--keepParent", bundle, target], check=True)
    entries.append({
        "id": plugin_id,
        "bundle": name,
        "file": archive,
        "sha256": sha256(target),
        "size": os.path.getsize(target),
        "installedSize": tree_size(bundle),
    })
    bundles.append(bundle)

if len(builds) > 1:
    sys.exit(f"插件包不是同一次构建的：{sorted(builds)}")
index = {"format": 1, "version": version, "build": builds.pop() if builds else "", "plugins": entries}
with open(os.path.join(out, f"plugins-{version}.json"), "w", encoding="utf-8") as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
    f.write("\n")

# 提交公证用：所有插件包放进一个压缩包
notary = os.path.join(out, "plugins-notary.zip")
if os.path.exists(notary):
    os.remove(notary)
if bundles:
    with tempfile.TemporaryDirectory() as folder:
        staging = os.path.join(folder, "plugins")
        os.mkdir(staging)
        for bundle in bundles:
            subprocess.run(["ditto", bundle, os.path.join(staging, os.path.basename(bundle))], check=True)
        subprocess.run(["ditto", "-c", "-k", "--keepParent", staging, notary], check=True)

for entry in entries:
    print(f"{entry['file']}：{entry['size']} 字节，装好后 {entry['installedSize']} 字节")
print(f"插件包列表：plugins-{version}.json（{len(entries)} 个）")
PY
