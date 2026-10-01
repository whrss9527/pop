#!/usr/bin/env bash
# 像用户双击一样启动 Pop.app，确认它没有闪退、创建了菜单栏图标，并且首次启动的设置窗口显示在最前面。
# Pop.app 旁边有插件包（scripts/build-app.sh 构建出来的 PopXxx.bundle）时，再测两件事：
#   1. 让 Pop 一起装载这些插件包，确认每个都装载上了；
#   2. 把插件包打成发布用的压缩包放进一个文件夹，当作发布页，设置里要一个插件包的功能，
#      让 Pop 自己下载、校验、解压、装上。
#
# 用法：scripts/launch-smoke.sh <Pop.app 路径>
set -euo pipefail

APP="${1:?用法: scripts/launch-smoke.sh <Pop.app 路径>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"

pkill -x Pop 2>/dev/null || true
# 等上一个 Pop（比如截图时开的）真的退出：还没退干净时 open 可能只是去叫醒它，带的环境变量就不生效了
for _ in $(seq 1 20); do
  pgrep -x Pop > /dev/null || break
  sleep 0.5
done
# 模拟全新安装：清掉上次留下的偏好设置
defaults delete "$BUNDLE_ID" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Pop.app 旁边的插件包
PLUGIN_DIR="$(cd "$(dirname "$APP")" && pwd)"
PLUGINS=()
# 和 PLUGINS 一一对应：插件包里可执行文件的路径（装载后会映射进 Pop 进程）
EXECUTABLES=()
for bundle in "$PLUGIN_DIR"/*.bundle; do
  [ -f "$bundle/Contents/Info.plist" ] || continue
  id="$(/usr/libexec/PlistBuddy -c 'Print :PopPluginID' "$bundle/Contents/Info.plist" 2>/dev/null)" || continue
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$bundle/Contents/Info.plist" 2>/dev/null)" || continue
  PLUGINS+=("$id")
  EXECUTABLES+=("$(basename "$bundle")/Contents/MacOS/${executable}")
done

START="$(date '+%Y-%m-%d %H:%M:%S')"
if [ ${#PLUGINS[@]} -gt 0 ]; then
  echo "一起装载的插件包：${PLUGINS[*]}"
  open --env "POP_PLUGIN_DIR=${PLUGIN_DIR}" "$APP"
else
  open "$APP"
fi
sleep 10

dump_logs() {
  echo "---- Pop 的系统日志 ----"
  log show --start "$START" --style compact --predicate 'process == "Pop"' 2>/dev/null | tail -60 || true
  for report in ~/Library/Logs/DiagnosticReports/Pop*; do
    [ -f "$report" ] || continue
    echo "---- 崩溃报告 $report ----"
    head -c 8000 "$report"
  done
}

if ! pgrep -x Pop > /dev/null; then
  echo "❌ Pop 启动后退出了"
  dump_logs
  exit 1
fi

WINDOWS_SCRIPT="$(mktemp -t pop-windows).swift"
cat > "$WINDOWS_SCRIPT" <<'EOF'
import CoreGraphics
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let layers = info
    .filter { ($0[kCGWindowOwnerName as String] as? String) == "Pop" }
    .compactMap { $0[kCGWindowLayer as String] as? Int }
print(layers.map(String.init).joined(separator: " "))
EOF
LAYERS="$(swift "$WINDOWS_SCRIPT")"
echo "Pop 的窗口层级：${LAYERS}"

# 首次启动应该弹出设置窗口（普通窗口，层级 0）
if ! grep -qw 0 <<< "$LAYERS"; then
  echo "❌ 没有看到首次启动的设置窗口"
  dump_logs
  exit 1
fi

# 菜单栏图标：macOS 15 及以前是 Pop 自己的窗口（层级 25）；
# macOS 26 起由控制中心托管，只能从 Pop 的日志里看到它请求了 NSStatusItemView 场景。
if ! grep -qw 25 <<< "$LAYERS" && \
   ! log show --start "$START" --style compact --predicate 'process == "Pop"' 2>/dev/null | grep -q "NSStatusItemView"; then
  echo "❌ 没有找到菜单栏图标"
  dump_logs
  exit 1
fi

if log show --start "$START" --style compact --predicate 'process == "Pop"' 2>/dev/null | grep -q "may order beneath the active application"; then
  echo "❌ 设置窗口是以非前台方式弹出的，会被其他 App 的窗口挡住"
  dump_logs
  exit 1
fi

# 每个插件包都装载上了：日志里有「loaded plugin <ID>」，或者它的可执行文件已经映射进 Pop 进程。
# 系统日志偶尔会晚到、在日志多的时候还会丢几条，所以多等一会儿，也用 lsof 看一眼
if [ ${#PLUGINS[@]} -gt 0 ]; then
  PID="$(pgrep -x Pop | head -1 || true)"
  for _ in $(seq 1 15); do
    PLUGIN_LOG="$(log show --start "$START" --style compact --predicate 'process == "Pop" AND category == "plugins"' 2>/dev/null || true)"
    MAPPED="$(lsof -p "$PID" 2>/dev/null || true)"
    MISSING=()
    for i in "${!PLUGINS[@]}"; do
      id="${PLUGINS[$i]}"
      grep -q "loaded plugin ${id} " <<< "$PLUGIN_LOG" && continue
      grep -qF "${EXECUTABLES[$i]}" <<< "$MAPPED" && continue
      MISSING+=("$id")
    done
    [ ${#MISSING[@]} -eq 0 ] && break
    sleep 1
  done
  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ 这些插件包没有装载上：${MISSING[*]}"
    echo "$PLUGIN_LOG" | tail -20
    echo "Pop 进程的环境变量：$(ps -E -ww -o command= -p "$PID" 2>/dev/null | grep -o 'POP_[A-Z_]*=[^ ]*' | tr '\n' ' ' || true)"
    dump_logs
    exit 1
  fi
  echo "插件包都装载上了：${PLUGINS[*]}"
fi

pkill -x Pop || true
echo "✅ Pop 启动正常：进程存活、有菜单栏图标、设置窗口在最前面"

[ ${#PLUGINS[@]} -gt 0 ] || exit 0

# 从「发布页」装插件包：挑一个 ID 和它提供的功能 ID 一样的插件包（提词器；没有的话用第一个），
# 把这个功能放到圆盘上，Pop 启动时就会去装它的插件包
INSTALL_ID="${PLUGINS[0]}"
for id in "${PLUGINS[@]}"; do
  [ "$id" = teleprompter ] && INSTALL_ID="$id"
done
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SOURCE="$(mktemp -d -t pop-plugin-source)"
"$ROOT/scripts/package-plugins.sh" "$PLUGIN_DIR" "$SOURCE" "$VERSION" > /dev/null
INSTALLED_DIR="$HOME/Library/Application Support/Pop/PluginBundles"
rm -rf "$INSTALLED_DIR"
for _ in $(seq 1 20); do
  pgrep -x Pop > /dev/null || break
  sleep 0.5
done
defaults delete "$BUNDLE_ID" 2>/dev/null || true
SETTINGS_HEX="$(python3 -c 'import json, sys; print(json.dumps({"ring": {"slots": ["translate", sys.argv[1], None, None]}, "installedPlugins": ["translate", sys.argv[1]]}).encode().hex())' "$INSTALL_ID")"
defaults write "$BUNDLE_ID" pop.settings.v1 -data "$SETTINGS_HEX"

START="$(date '+%Y-%m-%d %H:%M:%S')"
echo "从 ${SOURCE} 装插件包 ${INSTALL_ID}"
open --env "POP_PLUGIN_SOURCE=${SOURCE}" "$APP"
installed=""
for _ in $(seq 1 40); do
  if log show --start "$START" --style compact --predicate 'process == "Pop" AND category == "plugins"' 2>/dev/null | grep -q "installed plugin ${INSTALL_ID}"; then
    installed=1
    break
  fi
  sleep 1
done
PLUGIN_LOG="$(log show --start "$START" --style compact --predicate 'process == "Pop" AND category == "plugins"' 2>/dev/null || true)"
pkill -x Pop || true
if [ -z "$installed" ]; then
  echo "❌ 插件包 ${INSTALL_ID} 没有从发布页装上"
  echo "$PLUGIN_LOG" | tail -20
  ls -la "$SOURCE" || true
  dump_logs
  exit 1
fi
if ! grep -q "loaded plugin ${INSTALL_ID} " <<< "$PLUGIN_LOG" || [ ! -d "$INSTALLED_DIR" ]; then
  echo "❌ 插件包 ${INSTALL_ID} 下载了但没有装载"
  echo "$PLUGIN_LOG" | tail -20
  exit 1
fi
echo "装好的插件包：$(ls "$INSTALLED_DIR")"
# 恢复成全新安装的样子，后面的测试不受影响
rm -rf "$INSTALLED_DIR" "$SOURCE"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
echo "✅ 插件包能从发布页下载、校验、装上：${INSTALL_ID}"
