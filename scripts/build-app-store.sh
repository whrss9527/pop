#!/usr/bin/env bash
# 构建 Mac App Store 版并打成上传用的安装包：scripts/build-app.sh 的 App Store 版（POP_APPSTORE=1）→ 放进描述文件
# → 用 Apple Distribution 证书带沙盒签名（先签 Contents/PlugIns 里的插件包，再签 App）→ productbuild 打成
# dist/Pop-AppStore.pkg（用 Mac Installer Distribution 证书签名）。App Store 版不带 iCloud，描述文件不用开任何能力。
#
#   正式构建（需要证书和描述文件，见 docs/app-store.md）：
#     APPSTORE_PROFILE=Pop_Mac_App_Store.provisionprofile \
#     APP_SIGN_IDENTITY="Apple Distribution: 名字 (TEAMID)" \
#     INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: 名字 (TEAMID)" \
#     scripts/build-app-store.sh 0.65.0
#
#   CI 里没有证书时（ADHOC=1）：ad-hoc 签名，打一个不签名的 pkg，检查打包流程走得通。这样的 pkg 不能上传。
#
# 其他变量：
#   CODESIGN_KEYCHAIN   证书所在的钥匙串（CI 里导入到临时钥匙串）
#   POP_BUILD_NUMBER    构建号（CFBundleVersion）；每次上传都要比上次大，不设时用提交数
#
# 用法：scripts/build-app-store.sh <版本号>
# 产物：dist/appstore/Pop.app，dist/Pop-AppStore.pkg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: scripts/build-app-store.sh <版本号>}"
BUNDLE_ID="io.github.whrss9527.pop"
APP="dist/appstore/Pop.app"
PKG="dist/Pop-AppStore.pkg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ENTITLEMENTS="$WORK/Pop.entitlements"

fail() {
  echo "error: $*" >&2
  exit 1
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

cp Pop/Resources/Pop-Sandbox.entitlements "$ENTITLEMENTS"
if [ "${ADHOC:-0}" = "1" ]; then
  echo "==> ad-hoc 构建：不放描述文件，不签安装包"
  IDENTITY="-"
  PROFILE=""
  INSTALLER=""
else
  PROFILE="${APPSTORE_PROFILE:-}"
  IDENTITY="${APP_SIGN_IDENTITY:-}"
  INSTALLER="${INSTALLER_SIGN_IDENTITY:-}"
  [ -n "$PROFILE" ] && [ -f "$PROFILE" ] || fail "APPSTORE_PROFILE 要指向 Mac App Store 的描述文件（.provisionprofile）"
  [ -n "$IDENTITY" ] || fail "APP_SIGN_IDENTITY 没有设置（钥匙串里 Apple Distribution 证书的名字）"
  [ -n "$INSTALLER" ] || fail "INSTALLER_SIGN_IDENTITY 没有设置（钥匙串里 Mac Installer Distribution 证书的名字）"

  echo "==> 检查描述文件"
  security cms -D -i "$PROFILE" > "$WORK/profile.plist" || fail "读不了描述文件 $PROFILE"
  TEAM_ID="$(plist_value "$WORK/profile.plist" TeamIdentifier:0)"
  APP_ID="$(plist_value "$WORK/profile.plist" Entitlements:com.apple.application-identifier)"
  echo "    名称：$(plist_value "$WORK/profile.plist" Name)"
  echo "    团队：${TEAM_ID}，App ID：${APP_ID}，到期：$(plist_value "$WORK/profile.plist" ExpirationDate)"
  [ -n "$TEAM_ID" ] || fail "描述文件里没有团队 ID"
  [ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] || fail "描述文件的 App ID 是 ${APP_ID}，应该是 ${TEAM_ID}.${BUNDLE_ID}"
  # 开发用的描述文件列着测试设备；App Store 的没有
  if /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$WORK/profile.plist" > /dev/null 2>&1; then
    fail "这是开发用的描述文件（列着测试设备），上传要用“Mac App Store Connect”类型的描述文件"
  fi
  # 上传的 App 签名里要有 App ID 和团队 ID，和描述文件里的一样
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENTITLEMENTS"
fi
plutil -lint "$ENTITLEMENTS"

echo "==> 构建 App Store 版"
BUILT="$(POP_APPSTORE=1 scripts/build-app.sh "$VERSION" build/appstore | tail -n 1)"
rm -rf "$APP"
mkdir -p "$(dirname "$APP")"
ditto "$BUILT" "$APP"

echo "==> Info.plist"
info="$APP/Contents/Info.plist"
# 只用了系统自带的 HTTPS，属于豁免的加密：声明以后上传时不用再回答出口合规的问题
/usr/libexec/PlistBuddy -c "Delete :ITSAppUsesNonExemptEncryption" "$info" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "$info"
echo "    版本 $(plist_value "$info" CFBundleShortVersionString)，构建 $(plist_value "$info" CFBundleVersion)，类别 $(plist_value "$info" LSApplicationCategoryType)"

echo "==> 签名"
KEYCHAIN_ARGS=()
if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
  KEYCHAIN_ARGS=(--keychain "$CODESIGN_KEYCHAIN")
fi
for bundle in "$APP"/Contents/PlugIns/*.bundle; do
  codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} "$bundle"
done
if [ -n "$PROFILE" ]; then
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
fi
codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --entitlements "$ENTITLEMENTS" "$APP"

echo "==> 检查签名"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - --xml "$APP" > "$WORK/signed.plist"
plutil -p "$WORK/signed.plist"
[ "$(plist_value "$WORK/signed.plist" com.apple.security.app-sandbox)" = "true" ] || fail "签名里没有沙盒"
[ -n "$(find "$APP/Contents/PlugIns" -maxdepth 1 -name '*.bundle')" ] || fail "App 里没有插件包"
if [ -n "$PROFILE" ]; then
  [ -f "$APP/Contents/embedded.provisionprofile" ] || fail "App 里没有描述文件"
fi
lipo -info "$APP/Contents/MacOS/Pop"

echo "==> 打包 $PKG"
rm -f "$PKG"
PKG_ARGS=(--component "$APP" /Applications)
if [ -n "$INSTALLER" ]; then
  PKG_ARGS+=(--sign "$INSTALLER" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"})
fi
productbuild "${PKG_ARGS[@]}" "$PKG"
if [ -n "$INSTALLER" ]; then
  pkgutil --check-signature "$PKG"
fi
ls -la "$PKG"
echo "==> 完成：${PKG}（$(plist_value "$info" CFBundleShortVersionString) 构建 $(plist_value "$info" CFBundleVersion)）"
