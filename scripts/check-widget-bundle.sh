#!/usr/bin/env bash
# 隔离构建中的组件结构、版本、签名和注册校验。
set -euo pipefail
APP="${1:?需要 Pop.app 路径}"
WIDGET="$APP/Contents/PlugIns/PopWidgets.appex"
[[ -d "$WIDGET" ]]
HOST_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$WIDGET/Contents/Info.plist")" == "$HOST_ID.widgets" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$WIDGET/Contents/Info.plist")" == com.apple.widgetkit-extension ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$WIDGET/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" ]]
codesign --verify --deep --strict "$APP"
trap 'pluginkit -r "$WIDGET" >/dev/null 2>&1 || true' EXIT
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
pluginkit -a "$WIDGET"
for attempt in {1..15}; do
  listing=$(pluginkit -m -A -D -v -i "$HOST_ID.widgets")
  [[ "$listing" == *"$HOST_ID.widgets"* ]] && break
  sleep 1
done
[[ "$listing" == *"$HOST_ID.widgets"* ]]
echo 'Pop widget bundle and registration verified'
