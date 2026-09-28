#!/usr/bin/env bash
# 构建一个本地签名（ad-hoc）的 Release 版 Pop.app，给自己试用或者给 CI 做启动测试。
# 不带 iCloud 能力、不开强化运行时：本地签名 + 强化运行时会触发库校验，较新的 macOS 上可能直接启动失败。
#
# 用法：scripts/build-preview.sh <版本号> [输出目录]
# 成功后最后一行输出 Pop.app 的路径。
set -euo pipefail

VERSION="${1:?用法: scripts/build-preview.sh <版本号> [输出目录]}"
OUT="${2:-build/preview}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# CFBundleVersion 用提交数，和正式发布脚本保持一致
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

xcodegen generate > /dev/null

if ! xcodebuild build \
  -project Pop.xcodeproj \
  -scheme Pop \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$OUT/DerivedData" \
  -clonedSourcePackagesDirPath "$OUT/SourcePackages" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  POP_ENTITLEMENTS=Pop/Resources/Pop-NoCloud.entitlements \
  ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  > "$OUT/build.log" 2>&1; then
  grep -E "error:" "$OUT/build.log" | sort -u | head -50 >&2 || true
  tail -60 "$OUT/build.log" >&2
  exit 1
fi

APP="$OUT/DerivedData/Build/Products/Release/Pop.app"
codesign --verify --deep --strict "$APP"
echo "$APP"
