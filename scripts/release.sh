#!/usr/bin/env bash
# 打包、签名、公证 Pop，并发布到 GitHub Releases（App 内的「检查更新」从这里读取）。
#
# 用法：scripts/release.sh 0.2.0
#
# 一次性准备（见 README「发布新版本」）：
#   1. Xcode 登录付费开发者账号，钥匙串里有 Developer ID Application 证书；
#   2. 保存公证凭据：xcrun notarytool store-credentials pop-notary --apple-id <Apple ID> --team-id <Team ID>
#   3. 用 Sparkle 的 generate_keys 生成更新签名密钥（私钥存在钥匙串），公钥填到 Config/Pop.xcconfig；
#   4. 安装并登录 GitHub CLI：brew install gh && gh auth login
set -euo pipefail

VERSION="${1:?用法: scripts/release.sh <版本号，例如 0.2.0>}"
NOTARY_PROFILE="${NOTARY_PROFILE:-pop-notary}"
REPO="${REPO:-whrss9527/pop}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build/release"
cd "$ROOT"

if ! grep -Eq '^SPARKLE_PUBLIC_ED_KEY *= *[A-Za-z0-9+/=]{20,}' Config/Pop.xcconfig; then
  echo "❌ Config/Pop.xcconfig 里还没有配置 SPARKLE_PUBLIC_ED_KEY，用户将无法校验更新包。" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌ 工作区有未提交的修改，请先提交。" >&2
  exit 1
fi

# CFBundleVersion 用提交数，保证单调递增（Sparkle 用它比较新旧）。
BUILD_NUMBER="$(git rev-list --count HEAD)"

rm -rf "$BUILD"
mkdir -p "$BUILD/updates"

echo "==> 生成 Xcode 工程"
xcodegen generate

echo "==> Archive $VERSION ($BUILD_NUMBER)"
xcodebuild archive \
  -project Pop.xcodeproj \
  -scheme Pop \
  -configuration Release \
  -archivePath "$BUILD/Pop.xcarchive" \
  -clonedSourcePackagesDirPath "$BUILD/SourcePackages" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "==> 用 Developer ID 导出"
xcodebuild -exportArchive \
  -archivePath "$BUILD/Pop.xcarchive" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$BUILD/export"

APP="$BUILD/export/Pop.app"
ZIP="$BUILD/updates/Pop-$VERSION.zip"

echo "==> 公证（通常需要几分钟）"
ditto -c -k --keepParent "$APP" "$BUILD/Pop-notarize.zip"
xcrun notarytool submit "$BUILD/Pop-notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> 生成 appcast（用钥匙串里的 Sparkle 私钥签名）"
GENERATE_APPCAST="$(find "$BUILD/SourcePackages/artifacts" -type f -name generate_appcast -perm -u+x | head -n 1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "❌ 没找到 Sparkle 的 generate_appcast 工具" >&2
  exit 1
fi
"$GENERATE_APPCAST" \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  -o "$BUILD/appcast.xml" \
  "$BUILD/updates"

echo "==> 创建 GitHub Release v$VERSION"
gh release create "v$VERSION" "$ZIP" "$BUILD/appcast.xml" \
  --repo "$REPO" \
  --title "Pop $VERSION" \
  --generate-notes

echo "✅ 完成。已安装的 Pop 会通过 https://github.com/$REPO/releases/latest/download/appcast.xml 发现这个版本。"
