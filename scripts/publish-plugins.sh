#!/usr/bin/env bash
# 单独发布插件包：不发 Pop 新版本，把改了版本号的插件包加到最新正式版的发布页上，装着这个版本的 Pop 打开设置就能装上、
# 装着旧版本的会在后台换成新的。
#
# 插件包只能和同一次构建出来的 Pop 一起用（构建标识要一样），所以在最新正式版的标签上重新构建，只换上插件包自己的代码：
#   1. 找出要发布的：PluginBundles/<文件夹>/plugin.json 里的 version 和发布页插件包列表里的不一样（或者列表里还没有）
#   2. 在正式版的标签上（git worktree）放进这些插件包的代码，project.yml 里还没有的加上 target，构建
#   3. 用发布出去的那个 Pop 装载一遍新的插件包、自己从「发布页」装一次（scripts/launch-smoke.sh），确认能用
#   4. 打包、公证（证书是 Developer ID 时），合进发布页上的插件包列表，传上去（--dry-run 时不传）
# Pop 的新版本还没发布时（CHANGELOG.md 最上面的版本还没有标签）不发：插件包会跟着那个版本一起发布。
#
# 需要 gh（GH_TOKEN）、xcodegen；签名、公证的环境变量和发布流程一样（CODESIGN_*、NOTARY_*）。
# 用法：scripts/publish-plugins.sh [--dry-run] [插件包 ID …]   不写 ID 时发布所有改了版本号的
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DRY_RUN=""
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift
fi
REPO="${GITHUB_REPOSITORY:-whrss9527/pop}"
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pop-publish-plugins"
rm -rf "$WORK"
mkdir -p "$WORK"

TAG="$(gh release view --repo "$REPO" --json tagName -q .tagName)"
VERSION="${TAG#v}"
TOP="$(grep -m1 -E '^## [0-9]' CHANGELOG.md | sed -E 's/^## ([0-9][^（( ]*).*/\1/')"
if [ "$TOP" != "$VERSION" ] && ! gh release view "v${TOP}" --repo "$REPO" > /dev/null 2>&1; then
  echo "Pop ${TOP} 还没发布：插件包会跟着它一起发布，这次不单独发布"
  exit 0
fi
echo "最新正式版：${TAG}"

gh release download "$TAG" --repo "$REPO" --pattern "plugins-${VERSION}.json" --dir "$WORK"
INDEX="$WORK/plugins-${VERSION}.json"

# 要发布的插件包：「ID 文件夹 版本」一行一个
python3 - "$INDEX" "$@" > "$WORK/plan.txt" <<'PY'
import json, os, sys
index = json.load(open(sys.argv[1], encoding="utf-8"))
wanted = set(sys.argv[2:])
published = {entry["id"]: (entry.get("meta") or {}).get("version") for entry in index["plugins"]}
found = set()
for folder in sorted(os.listdir("PluginBundles")):
    path = os.path.join("PluginBundles", folder, "plugin.json")
    if not os.path.isfile(path):
        continue
    meta = json.load(open(path, encoding="utf-8"))
    plugin_id, version = meta.get("id"), meta.get("version")
    if not plugin_id or not version:
        sys.exit(f"{path} 里要写 id 和 version")
    found.add(plugin_id)
    if wanted and plugin_id not in wanted:
        continue
    if not wanted and published.get(plugin_id) == version:
        continue
    print(plugin_id, folder, version)
unknown = wanted - found
if unknown:
    sys.exit(f"找不到这些插件包的 plugin.json：{' '.join(sorted(unknown))}")
PY
if [ ! -s "$WORK/plan.txt" ]; then
  echo "没有要发布的插件包：plugin.json 里的版本和发布页上的一样"
  exit 0
fi
echo "要发布的插件包："
sed 's/^/  /' "$WORK/plan.txt"

# 在正式版的代码上放进这些插件包
git worktree add --detach "$WORK/release" "$TAG" > /dev/null
trap 'git -C "$ROOT" worktree remove --force "$WORK/release" > /dev/null 2>&1 || true' EXIT
while read -r plugin_id folder version; do
  rm -rf "$WORK/release/PluginBundles/${folder}"
  cp -R "PluginBundles/${folder}" "$WORK/release/PluginBundles/${folder}"
  python3 - "$WORK/release/project.yml" "$plugin_id" "$folder" <<'PY'
import sys
path, plugin_id, folder = sys.argv[1:4]
target = "Pop" + folder
text = open(path, encoding="utf-8").read()
if f"\n  {target}:\n" in text:
    sys.exit(0)
# 正式版的 project.yml 里还没有这个插件包：照 PopPlugin 模板加一个 target，放进 Pop 这个 scheme 一起构建
definition = f"""  {target}:
    templates: [PopPlugin]
    sources: [PluginBundles/{folder}]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.whrss9527.pop.plugin.{plugin_id}
        POP_PLUGIN_ID: {plugin_id}
        POP_PLUGIN_ENTRY: {target}Entry

"""
marker = "\n  PopTests:\n"
if marker not in text or "\n        Pop: all\n" not in text:
    sys.exit("正式版的 project.yml 里找不到 PopTests 或者 scheme 的构建列表")
text = text.replace(marker, "\n" + definition + marker[1:], 1)
text = text.replace("\n        Pop: all\n", f"\n        Pop: all\n        {target}: all\n", 1)
open(path, "w", encoding="utf-8").write(text)
print(f"在正式版的 project.yml 里加上了 {target}")
PY
done < "$WORK/plan.txt"

echo "在 ${TAG} 上构建"
APP="$(cd "$WORK/release" && scripts/build-app.sh "$VERSION" "$WORK/build" | tail -n 1)"
PRODUCTS="$(dirname "$APP")"

# 发布出去的那个 Pop 和新的插件包放在一起，用它装载、自己装一次
gh release download "$TAG" --repo "$REPO" --pattern "Pop-${VERSION}.zip" --dir "$WORK"
mkdir -p "$WORK/check" "$WORK/bundles"
ditto -x -k "$WORK/Pop-${VERSION}.zip" "$WORK/check"
BUILD="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["build"])' "$INDEX")"
while read -r plugin_id folder version; do
  bundle="$PRODUCTS/Pop${folder}.bundle"
  [ -d "$bundle" ] || { echo "没有构建出 Pop${folder}.bundle"; exit 1; }
  built="$(/usr/libexec/PlistBuddy -c 'Print :PopBuildID' "$bundle/Contents/Info.plist")"
  if [ "$built" != "$BUILD" ]; then
    echo "Pop${folder}.bundle 的构建标识是 ${built}，发布页上的是 ${BUILD}：对不上，发布出去的 Pop 装不上"
    exit 1
  fi
  ditto "$bundle" "$WORK/bundles/Pop${folder}.bundle"
  ditto "$bundle" "$WORK/check/Pop${folder}.bundle"
done < "$WORK/plan.txt"
"$ROOT/scripts/launch-smoke.sh" "$WORK/check/Pop.app"
pkill -x Pop 2>/dev/null || true

# 打包；证书是 Developer ID、配了公证凭据时公证
scripts/package-plugins.sh "$WORK/bundles" "$WORK/dist" "$VERSION"
if [[ "${CODESIGN_NAME:-}" == "Developer ID Application:"* ]] && { [ -n "${NOTARY_KEY_P8:-}" ] || [ -n "${NOTARY_APPLE_ID:-}" ]; }; then
  if [ -n "$DRY_RUN" ]; then
    echo "只检查：不提交公证"
  else
    scripts/notarize.sh "$WORK/dist/plugins-notary.zip"
  fi
fi

# 合进发布页上的插件包列表：同一个 ID 的换掉，新的加在后面
python3 - "$INDEX" "$WORK/dist/plugins-${VERSION}.json" <<'PY'
import json, sys
index_path, new_path = sys.argv[1:3]
index = json.load(open(index_path, encoding="utf-8"))
new = json.load(open(new_path, encoding="utf-8"))
if new["build"] != index["build"]:
    sys.exit(f"构建标识对不上：{new['build']} 和 {index['build']}")
entries = {entry["id"]: entry for entry in new["plugins"]}
merged = [entries.pop(entry["id"], entry) for entry in index["plugins"]]
merged += entries.values()
index["plugins"] = merged
with open(new_path, "w", encoding="utf-8") as f:
    json.dump(index, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"插件包列表里一共 {len(merged)} 个")
PY

assets=("$WORK/dist/plugins-${VERSION}.json")
while read -r plugin_id folder version; do
  assets+=("$WORK/dist/plugin-${plugin_id}.zip")
done < "$WORK/plan.txt"
if [ -n "$DRY_RUN" ]; then
  echo "只检查，不上传：${assets[*]##*/}"
  exit 0
fi
gh release upload "$TAG" "${assets[@]}" --repo "$REPO" --clobber
echo "已经发布到 https://github.com/${REPO}/releases/tag/${TAG}："
sed 's/^/  /' "$WORK/plan.txt"
