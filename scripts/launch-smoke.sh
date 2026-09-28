#!/usr/bin/env bash
# 像用户双击一样启动 Pop.app，确认它没有闪退、创建了菜单栏图标，并且首次启动的设置窗口显示在最前面。
#
# 用法：scripts/launch-smoke.sh <Pop.app 路径>
set -euo pipefail

APP="${1:?用法: scripts/launch-smoke.sh <Pop.app 路径>}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"

pkill -x Pop 2>/dev/null || true
# 模拟全新安装：清掉上次留下的偏好设置
defaults delete "$BUNDLE_ID" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

START="$(date '+%Y-%m-%d %H:%M:%S')"
open "$APP"
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

pkill -x Pop || true
echo "✅ Pop 启动正常：进程存活、有菜单栏图标、设置窗口在最前面"
