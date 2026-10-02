#!/usr/bin/env bash
# 构建 Release 版 Pop.app（Apple 芯片 / Intel 通用），发布流程、CI 的启动测试和自己试用都用它。
# 不带 iCloud 能力（需要付费开发者账号和描述文件，见 README）。
#
# 签名见 scripts/sign-app.sh：默认本地签名（ad-hoc）；设置了 CODESIGN_IDENTITY 时用证书重新签名。
# 本地签名时不开 Hardened Runtime：本地签名 + Hardened Runtime 会触发库校验，较新的 macOS 上可能直接启动失败。
#
# POP_SANDBOX=1 时构建 Mac App Store 版的试用包：编译时带 APP_STORE（见 Pop/App/Distribution.swift），
# 开 App Sandbox（Pop/Resources/Pop-Sandbox.entitlements），改名成 Pop2（App 名、进程名、Bundle ID io.github.whrss9527.pop2
# 都和 Pop 分开），可以和装着的 Pop 放在一起，辅助功能列表里也分得清；最后一行输出的是 Pop2.app 的路径。
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

ENTITLEMENTS=Pop/Resources/Pop-NoCloud.entitlements
FLAVOR_SETTINGS=()
if [ "${POP_SANDBOX:-}" = "1" ]; then
  ENTITLEMENTS=Pop/Resources/Pop-Sandbox.entitlements
  FLAVOR_SETTINGS=("POP_BUNDLE_ID=io.github.whrss9527.pop2" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) APP_STORE')
  echo "沙盒验证包 Pop2：${ENTITLEMENTS}，Bundle ID io.github.whrss9527.pop2" >&2
fi

# CI 的启动测试（版本号 0.0.0-ci）在 macOS 26 上只编这台机器的架构：那台 runner 编得慢，整个启动测试有 30 分钟的上限。
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
  POP_ENTITLEMENTS="$ENTITLEMENTS" \
  ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  ${ARCH_SETTINGS[@]+"${ARCH_SETTINGS[@]}"} \
  ${FLAVOR_SETTINGS[@]+"${FLAVOR_SETTINGS[@]}"} \
  > "$OUT/build.log" 2>&1; then
  grep -E "error:" "$OUT/build.log" | sort -u | head -50 >&2 || true
  tail -60 "$OUT/build.log" >&2
  exit 1
fi

APP="$OUT/DerivedData/Build/Products/Release/Pop.app"
if [ "${POP_SANDBOX:-}" = "1" ]; then
  # 复制一份改名成 Pop2：文件名、可执行文件名（也就是进程名）和显示的名字都换掉，改完重新签名
  POP2="$(dirname "$APP")/Pop2.app"
  rm -rf "$POP2"
  ditto "$APP" "$POP2"
  mv "$POP2/Contents/MacOS/Pop" "$POP2/Contents/MacOS/Pop2"
  for key in CFBundleExecutable CFBundleName CFBundleDisplayName; do
    /usr/libexec/PlistBuddy -c "Set :$key Pop2" "$POP2/Contents/Info.plist"
  done
  # App Store 版不带赞赏码（审核指南 3.1.1）
  rm -f "$POP2/Contents/Resources/donate-wechat.png"
  # App Store 版不从网上下载插件包（审核指南 2.5.2）：都打进 App 里（Contents/PlugIns），装上时从这里装载。
  # 沙盒里跑不了的不打进去，和 PluginCatalog.unavailableInAppStore 对应
  APP_STORE_EXCLUDED_PLUGINS=" PopZip PopSystemActions PopEncryptFiles PopBluetooth "
  mkdir -p "$POP2/Contents/PlugIns"
  for bundle in "$(dirname "$APP")"/Pop*.bundle; do
    [ -f "$bundle/Contents/Info.plist" ] || continue
    case "$APP_STORE_EXCLUDED_PLUGINS" in *" $(basename "$bundle" .bundle) "*) continue ;; esac
    target="$POP2/Contents/PlugIns/$(basename "$bundle")"
    ditto "$bundle" "$target"
    codesign --force --sign "${CODESIGN_IDENTITY:--}" ${CODESIGN_KEYCHAIN:+--keychain "$CODESIGN_KEYCHAIN"} "$target"
  done
  echo "打进 App 的插件包：$(find "$POP2/Contents/PlugIns" -maxdepth 1 -name '*.bundle' | wc -l | tr -d ' ') 个" >&2
  APP="$POP2"
  if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --sign - --entitlements "$ROOT/$ENTITLEMENTS" "$APP"
  fi
fi
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
