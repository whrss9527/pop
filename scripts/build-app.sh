#!/usr/bin/env bash
# 构建 Release 版 Pop.app（Apple 芯片 / Intel 通用），发布流程、CI 的启动测试和自己试用都用它。
# 不带 iCloud 能力（需要付费开发者账号和描述文件，见 README）。
#
# 签名见 scripts/sign-app.sh：默认本地签名（ad-hoc）；设置了 CODESIGN_IDENTITY 时用证书重新签名。
# 本地签名时不开 Hardened Runtime：本地签名 + Hardened Runtime 会触发库校验，较新的 macOS 上可能直接启动失败。
#
# 用法：scripts/build-app.sh <版本号> [输出目录]
# 成功后最后一行输出 Pop.app 的路径（其他信息都打到标准错误）；插件包（PopXxx.bundle）在 Pop.app 旁边。
set -euo pipefail

VERSION="${1:?用法: scripts/build-app.sh <版本号> [输出目录]}"
OUT="${2:-build/app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# CFBundleVersion 用提交数，保证单调递增
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# 这次构建的标识：插件包只装载到同一次构建出来的 Pop 里
BUILD_ID="${VERSION}+$(git rev-parse --short=12 HEAD 2>/dev/null || echo local)"

xcodegen generate > /dev/null

# CI 的启动测试（版本号 0.0.0-ci）在 macOS 26 上只编这台机器的架构：那台 runner 编得慢，整个启动测试有时间上限（ci.yml 的 timeout-minutes）。
# macOS 15 上照样编 Apple 芯片和 Intel 的通用版，Intel 那份也要编得过；发布时总是通用版
ARCH_SETTINGS=()
if [ "$VERSION" = "0.0.0-ci" ] && [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]; then
  ARCH_SETTINGS=("ARCHS=$(uname -m)")
  echo "只编 $(uname -m)" >&2
fi

if ! xcodebuild build \
  -project Pop.xcodeproj \
  -scheme Pop \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$OUT/DerivedData" \
  -clonedSourcePackagesDirPath "$OUT/SourcePackages" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  POP_BUILD_ID="$BUILD_ID" \
  POP_ENTITLEMENTS=Pop/Resources/Pop-NoCloud.entitlements \
  ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ${ARCH_SETTINGS[@]+"${ARCH_SETTINGS[@]}"} \
  > "$OUT/build.log" 2>&1; then
  grep -E "error:" "$OUT/build.log" | sort -u | head -50 >&2 || true
  tail -60 "$OUT/build.log" >&2
  exit 1
fi

APP="$OUT/DerivedData/Build/Products/Release/Pop.app"
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  "$ROOT/scripts/sign-app.sh" "$APP" >&2
  echo "签名：$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')" >&2
else
  codesign --verify --deep --strict "$APP"
  echo "签名：本地签名（ad-hoc）" >&2
fi
# 插件包和 Pop.app 放在同一个文件夹里，用同一张证书签名
"$ROOT/scripts/sign-plugins.sh" "$(dirname "$APP")" >&2
echo "$APP"
