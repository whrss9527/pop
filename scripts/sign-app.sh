#!/usr/bin/env bash
# 给 Pop.app 签名。
#   不设 CODESIGN_IDENTITY：本地签名（ad-hoc），不开 Hardened Runtime。每次构建的签名都不一样，
#     macOS 会把新版本当成另一个程序，更新后要重新授权辅助功能。
#   CODESIGN_IDENTITY=证书名字或 SHA-1：用证书签名，开 Hardened Runtime、带安全时间戳；
#     CODESIGN_KEYCHAIN 可以指定证书所在的钥匙串。证书不变，签名的「身份」就不变，更新后授权不会丢。
#
# 用法：scripts/sign-app.sh <Pop.app>
set -euo pipefail

APP="${1:?用法: scripts/sign-app.sh <Pop.app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Pop/Resources/Pop-NoCloud.entitlements"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  # 插件包：Developer ID 证书带团队 ID，开着库校验也能装载同一个团队签名的插件包；
  # 自己生成的证书没有团队 ID，库校验会拦下所有插件包，这时关掉库校验，由 Pop 自己检查插件包是不是同一张证书签的
  if [[ "${CODESIGN_NAME:-$CODESIGN_IDENTITY}" != "Developer ID Application:"* ]]; then
    custom="$(mktemp -d)/Pop.entitlements"
    cp "$ENTITLEMENTS" "$custom"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$custom"
    ENTITLEMENTS="$custom"
  fi
  args=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
  if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
else
  args=(--force --sign - --entitlements "$ENTITLEMENTS")
fi

# 小组件使用独立沙盒声明，先按同一身份签名，再签外层 App。
widget_args=(--force --sign "${CODESIGN_IDENTITY:--}" --entitlements "$ROOT/Widgets/PopWidgets.entitlements")
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then widget_args+=(--options runtime --timestamp); fi
if [[ -n "${CODESIGN_KEYCHAIN:-}" ]]; then widget_args+=(--keychain "$CODESIGN_KEYCHAIN"); fi
for widget in "$APP"/Contents/PlugIns/*.appex; do
  [[ -d "$widget" ]] || continue
  codesign "${widget_args[@]}" "$widget"
done
codesign "${args[@]}" "$APP"
codesign --verify --deep --strict "$APP"
