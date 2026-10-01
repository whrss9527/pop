#!/usr/bin/env bash
# 给文件夹里的插件包（Info.plist 里有 PopPluginID 的 .bundle）签名，用和 Pop.app 一样的证书（见 scripts/sign-app.sh）：
#   设置了 CODESIGN_IDENTITY：用证书签名，开 Hardened Runtime、带安全时间戳；CODESIGN_KEYCHAIN 可以指定钥匙串。
#   没设置：本地签名（ad-hoc）。
# Pop 只装载和它自己同一张证书签名的插件包；本地签名的 Pop 只检查插件包的签名是否完整。
#
# 用法：scripts/sign-plugins.sh <放着插件包的文件夹>
set -euo pipefail

DIR="${1:?用法: scripts/sign-plugins.sh <放着插件包的文件夹>}"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  args=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
  if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
else
  args=(--force --sign -)
fi

count=0
for bundle in "$DIR"/*.bundle; do
  [ -f "$bundle/Contents/Info.plist" ] || continue
  /usr/libexec/PlistBuddy -c 'Print :PopPluginID' "$bundle/Contents/Info.plist" > /dev/null 2>&1 || continue
  codesign "${args[@]}" "$bundle"
  codesign --verify --strict "$bundle"
  count=$((count + 1))
done
echo "签好了 ${count} 个插件包"
