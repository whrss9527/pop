#!/usr/bin/env bash
# 构建 Release 版 Pop.app（Apple 芯片 / Intel 通用），发布流程、CI 的启动测试和自己试用都用它。
# 不带 iCloud 能力（需要付费开发者账号和描述文件，见 README）。
#
# 签名见 scripts/sign-app.sh：默认本地签名（ad-hoc）；设置了 CODESIGN_IDENTITY 时用证书重新签名。
# 本地签名时不开 Hardened Runtime：本地签名 + Hardened Runtime 会触发库校验，较新的 macOS 上可能直接启动失败。
#
# POP_APPSTORE=1 时构建 Mac App Store 版：编译时带 APP_STORE（见 Pop/App/Distribution.swift），开 App Sandbox
# （Pop/Resources/Pop-Sandbox.entitlements），不带赞赏码，插件包都打进 App 里（Contents/PlugIns）。这里只做本地签名，
# 上传用的签名和打包见 scripts/build-app-store.sh。
# POP_SANDBOX=1 在 App Store 版的基础上改名成 Pop2（App 名、进程名、Bundle ID io.github.whrss9527.pop2 都和 Pop 分开），
# 可以和装着的 Pop 放在一起试，辅助功能列表里也分得清；最后一行输出的是 Pop2.app 的路径。
# POP_BUILD_NUMBER 指定 CFBundleVersion（App Store 每次上传的构建号都要比上次大），不设时用提交数。
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
BUILD_NUMBER="${POP_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# 这次构建的标识：插件包只装载到同一次构建出来的 Pop 里
BUILD_ID="${VERSION}+$(git rev-parse --short=12 HEAD 2>/dev/null || echo local)"

xcodegen generate > /dev/null

APPSTORE=0
if [ "${POP_APPSTORE:-}" = "1" ] || [ "${POP_SANDBOX:-}" = "1" ]; then
  APPSTORE=1
fi
ENTITLEMENTS=Pop/Resources/Pop-NoCloud.entitlements
FLAVOR_SETTINGS=()
if [ "$APPSTORE" = "1" ]; then
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    echo "App Store 版在这里只做本地签名，上传用的签名见 scripts/build-app-store.sh" >&2
    exit 1
  fi
  ENTITLEMENTS=Pop/Resources/Pop-Sandbox.entitlements
  FLAVOR_SETTINGS=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) APP_STORE')
  if [ "${POP_SANDBOX:-}" = "1" ]; then
    FLAVOR_SETTINGS+=("POP_BUNDLE_ID=io.github.whrss9527.pop2")
    echo "App Store 版的试用包 Pop2：${ENTITLEMENTS}，Bundle ID io.github.whrss9527.pop2" >&2
  else
    echo "Mac App Store 版：${ENTITLEMENTS}" >&2
  fi
fi

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
PRODUCTS="$(dirname "$APP")"
if [ "$APPSTORE" = "1" ]; then
  if [ "${POP_SANDBOX:-}" = "1" ]; then
    # 复制一份改名成 Pop2：文件名、可执行文件名（也就是进程名）和显示的名字都换掉
    POP2="$PRODUCTS/Pop2.app"
    rm -rf "$POP2"
    ditto "$APP" "$POP2"
    mv "$POP2/Contents/MacOS/Pop" "$POP2/Contents/MacOS/Pop2"
    for key in CFBundleExecutable CFBundleName CFBundleDisplayName; do
      /usr/libexec/PlistBuddy -c "Set :$key Pop2" "$POP2/Contents/Info.plist"
    done
    APP="$POP2"
  fi
  # App Store 版不带赞赏码（审核指南 3.1.1）
  rm -f "$APP/Contents/Resources/donate-wechat.png"
  # App Store 版用不到的权限说明也去掉，免得审核时以为要用：蓝牙设备插件不打进去，也不给别的 App 发 Apple 事件
  for key in NSBluetoothAlwaysUsageDescription NSAppleEventsUsageDescription; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$APP/Contents/Info.plist" 2>/dev/null || true
  done
  # App Store 版不从网上下载插件包（审核指南 2.5.2）：都打进 App 里（Contents/PlugIns），装上时从这里装载。
  # 沙盒里跑不了的不打进去，和 PluginCatalog.unavailableInAppStore 对应
  APP_STORE_EXCLUDED_PLUGINS=" PopZip PopSystemActions PopEncryptFiles PopBluetooth PopQuitApps PopUninstallApp PopNewFile PopSendToPhone "
  rm -rf "$APP/Contents/PlugIns"
  mkdir -p "$APP/Contents/PlugIns"
  for bundle in "$PRODUCTS"/Pop*.bundle; do
    [ -f "$bundle/Contents/Info.plist" ] || continue
    case "$APP_STORE_EXCLUDED_PLUGINS" in *" $(basename "$bundle" .bundle) "*) continue ;; esac
    # 单独发布的插件包（带 plugin.json）要从发布页的插件包列表里认出来，App Store 版不读这个列表，也就不打进去
    [ -f "$bundle/Contents/Resources/plugin.json" ] && continue
    target="$APP/Contents/PlugIns/$(basename "$bundle")"
    ditto "$bundle" "$target"
    codesign --force --sign - "$target"
  done
  echo "打进 App 的插件包：$(find "$APP/Contents/PlugIns" -maxdepth 1 -name '*.bundle' | wc -l | tr -d ' ') 个" >&2
  codesign --force --sign - --entitlements "$ROOT/$ENTITLEMENTS" "$APP"
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
