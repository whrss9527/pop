#!/usr/bin/env bash
# 给浮窗拍一组截图：用演示模式启动 Pop（POP_DEMO=1，动画放慢 POP_ANIMATION_SCALE 倍），
# 按 Pop 写出的步骤时间在固定的时刻截下浮窗那一块，最后一起转成 JPEG。
# 圆盘展开、指向、滑动、选中、结果卡片、提示、列表、取消、贴图、常用短语、文本对比、图片配色、暂存架、打开方式、
# Markdown 预览、截图标注都会拍到，包括动画的中间帧。
# 之后用深色外观再拍一组停下来之后的样子（文件名以 dark- 开头），POP_SKIP_DARK=1 时不拍。
#
# 用法：scripts/overlay-screenshots.sh <Pop.app> <输出目录> [动画放慢倍数，默认 6]
set -euo pipefail

APP="${1:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
OUT="${2:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
SCALE="${3:-6}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d -t pop-screenshots)"
# 插件库读仓库里的索引，不联网
PLUGIN_INDEX="file://$(cd "$(dirname "$0")/.." && pwd)/plugins/index.json"

pkill -x Pop 2>/dev/null || true
for _ in $(seq 1 20); do
  pgrep -x Pop > /dev/null || break
  sleep 0.5
done
# 之前启动时留下的辅助功能授权提示框会挡在浮窗后面，先关掉
pkill -f universalAccessAuthWarn 2>/dev/null || true

# 「减弱动态效果」「降低透明度」打开时，玻璃是不透明的，动画也只剩淡入淡出，截图看不出效果。
# 先看看现在的设置，能关就关掉（关不掉也继续，演示模式本身会忽略「减弱动态效果」）
for key in reduceMotion reduceTransparency; do
  echo "${key}：$(defaults read com.apple.universalaccess "$key" 2>/dev/null || echo 未设置)"
  defaults write com.apple.universalaccess "$key" -bool false 2>/dev/null || echo "改不了 ${key}"
done

# 跑一遍演示并截图。参数：外观（light / dark）、动画放慢倍数、截图文件名前缀
run_demo() {
  local appearance="$1" scale="$2" prefix="$3"
  local log="$WORK/demo-${appearance}.log"
  pkill -x Pop 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x Pop > /dev/null || break
    sleep 0.5
  done
  # Pop.app 旁边的插件包一起装载，演示里也有插件包的步骤
  open -n --env POP_DEMO=1 --env "POP_ANIMATION_SCALE=${scale}" --env "POP_DEMO_LOG=${log}" \
    --env "POP_APPEARANCE=${appearance}" --env "POP_PLUGIN_INDEX_URL=${PLUGIN_INDEX}" \
    --env "POP_PLUGIN_DIR=$(cd "$(dirname "$APP")" && pwd)" "$APP"
  python3 - "$log" "$WORK" "$OUT" "$scale" "$appearance" "$prefix" <<'PY'
import os, subprocess, sys, time

log_path, work, out, scale, appearance, prefix = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5], sys.argv[6]

# 每一步开始后第几秒截图（按放慢 6 倍设计，别的倍数按比例换算）
plan = [
    ("ring", [0.25, 0.8, 1.4, 2.2]),
    ("loaded", [0.6, 2.6]),
    ("hover", [0.5, 3.0]),
    ("slide", [0.35, 0.9, 3.0]),
    ("commit", [0.3, 0.9, 1.6, 5.0]),
    ("toast", [0.4, 1.2, 5.0]),
    ("chooser", [0.6, 4.0]),
    ("ring2", [3.5]),
    ("cancel", [0.2, 0.5, 0.9]),
    ("press", [0.8, 3.0]),
    ("drag-up", [0.6, 2.4]),
    ("drag-clipboard", [0.5, 2.4]),
    ("release", [0.4, 1.2, 3.5]),
    ("unit", [0.6, 3.0]),
    ("pin", [0.3, 1.0, 3.0]),
    ("unpin", [0.4]),
    ("ai", [0.6, 3.0]),
    ("layout", [3.0]),
    ("translate", [3.0]),
    ("translate-compare", [3.0]),
    ("snippets", [0.6, 3.0]),
    ("diff", [3.0]),
    ("palette", [3.0]),
    ("shelf", [3.0]),
    ("openWith", [3.0]),
    ("markdown", [3.0]),
    ("extract", [3.0]),
    ("jsonTypes", [3.0]),
    ("toMarkdown", [3.0]),
    ("regex", [3.0]),
    ("history", [3.0]),
    ("history-search", [3.0]),
    ("reminder", [3.0]),
    ("table", [3.0]),
    ("photo", [3.0]),
    ("rename", [3.0]),
    ("sql", [3.0]),
    ("vocabulary", [3.0]),
    ("duplicates", [3.0]),
    ("pdfPages", [3.0]),
    ("diskUsage", [3.0]),
    ("tidyFolder", [3.0]),
    ("uninstallApp", [3.0]),
    ("newFile", [3.0]),
    ("fileEncoding", [3.0]),
    ("appInfo", [3.0]),
    ("similarPhotos", [3.0]),
    ("mediaInfo", [3.0]),
    ("subtitles", [3.0]),
    ("fontPreview", [3.0]),
    ("encryptFiles", [3.0]),
    ("batteryInfo", [3.0]),
    ("voiceRecorder", [3.0]),
    ("systemInfo", [3.0]),
    ("soundDevices", [3.0]),
    ("resolution", [3.0]),
    ("pdfPassword", [3.0]),
    ("toolbar", [0.3, 1.2]),
    ("watermark", [3.0]),
    ("sendToPhone", [3.0]),
    ("idNumber", [3.0]),
    ("transcribe", [3.0]),
    ("idPhoto", [3.0]),
    ("webCapture", [3.0]),
    ("cropImage", [3.0]),
    ("beautify", [3.0]),
    ("compareImages", [3.0]),
    ("splitImage", [3.0]),
    ("appIcon", [3.0]),
    ("screenRecord-picker", [1.0]),
    ("screenRecord-countdown", [0.5]),
    ("screenRecord-recording", [0.6]),
    ("screenRecord", [3.0]),
    ("systemActions", [3.0]),
    ("textImage", [3.0]),
    ("menuShortcuts", [0.6, 3.0]),
    ("quitApps", [3.0]),
    ("scrollCapture-capturing", [0.6]),
    ("scrollCapture", [3.0]),
    ("screenPen", [3.0]),
    ("cameraBubble", [3.0]),
    ("pointerHighlight", [0.3, 1.5]),
    ("teleprompter", [1.0]),
    ("spotlight", [1.0]),
    ("zoom", [1.0]),
    ("annotate", [1.5]),
    ("settings-plugins", [0.5]),
    ("settings-ai", [0.5]),
    ("settings-hotKeys", [0.5]),
    ("settings-pluginLibrary", [0.8]),
]
if appearance == "dark":
    # 深色外观只拍停下来之后的样子
    plan = [("loaded", [2.6]), ("slide", [3.0]), ("commit", [5.0]), ("toast", [1.2]), ("chooser", [4.0]),
            ("drag-clipboard", [2.4]), ("release", [3.5]), ("unit", [3.0]), ("pin", [3.0]), ("ai", [3.0]),
            ("layout", [3.0]), ("translate", [3.0]), ("translate-compare", [3.0]), ("snippets", [3.0]), ("diff", [3.0]), ("palette", [3.0]),
            ("shelf", [3.0]), ("openWith", [3.0]), ("markdown", [3.0]), ("extract", [3.0]), ("jsonTypes", [3.0]),
            ("toMarkdown", [3.0]), ("regex", [3.0]), ("history", [3.0]), ("history-search", [3.0]),
            ("reminder", [3.0]), ("table", [3.0]), ("photo", [3.0]), ("rename", [3.0]), ("sql", [3.0]), ("vocabulary", [3.0]),
            ("duplicates", [3.0]), ("pdfPages", [3.0]), ("diskUsage", [3.0]), ("tidyFolder", [3.0]), ("uninstallApp", [3.0]), ("newFile", [3.0]), ("fileEncoding", [3.0]), ("appInfo", [3.0]), ("similarPhotos", [3.0]), ("mediaInfo", [3.0]), ("subtitles", [3.0]), ("fontPreview", [3.0]), ("encryptFiles", [3.0]), ("batteryInfo", [3.0]), ("voiceRecorder", [3.0]), ("systemInfo", [3.0]), ("soundDevices", [3.0]), ("resolution", [3.0]), ("pdfPassword", [3.0]),
            ("toolbar", [1.2]), ("watermark", [3.0]), ("sendToPhone", [3.0]), ("idNumber", [3.0]), ("transcribe", [3.0]),
            ("idPhoto", [3.0]), ("webCapture", [3.0]), ("cropImage", [3.0]), ("beautify", [3.0]), ("compareImages", [3.0]), ("splitImage", [3.0]), ("appIcon", [3.0]),
            ("screenRecord-picker", [1.0]), ("screenRecord-countdown", [0.5]), ("screenRecord-recording", [0.6]), ("screenRecord", [3.0]), ("systemActions", [3.0]), ("textImage", [3.0]),
            ("menuShortcuts", [3.0]), ("quitApps", [3.0]), ("scrollCapture", [3.0]), ("screenPen", [3.0]), ("cameraBubble", [3.0]), ("pointerHighlight", [1.5]), ("teleprompter", [1.0]), ("spotlight", [1.0]), ("zoom", [1.0]), ("annotate", [1.5]),
            ("settings-plugins", [0.5]), ("settings-ai", [0.5]), ("settings-hotKeys", [0.5]),
            ("settings-pluginLibrary", [0.8])]
factor = scale / 6.0

def markers():
    result = {}
    region = None
    if os.path.exists(log_path):
        for line in open(log_path, encoding="utf-8").read().splitlines():
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "region" and len(parts) >= 7:
                region = [int(p) for p in parts[1:7]]
            elif len(parts) >= 2:
                result[parts[0]] = float(parts[1])
    return result, region

def wait_for(name, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found, region = markers()
        if name in found:
            return found[name], region
        time.sleep(0.03)
    raise SystemExit(f"等不到演示步骤 {name}，Pop 可能没有启动")

def screen_rect(region):
    """截图区域换成 screencapture -R 用的矩形：AppKit 坐标 y 向上，-R 的 y 向下；超出屏幕的部分去掉"""
    x, y, w, h, screen_w, screen_h = region
    left = max(0, x)
    top = max(0, screen_h - y - h)
    right = min(screen_w, x + w)
    bottom = min(screen_h, screen_h - y)
    return left, top, max(1, right - left), max(1, bottom - top)

shots = []
index = 0
for name, offsets in plan:
    start, _ = wait_for(name)
    for offset in offsets:
        target = start + offset * factor
        delay = target - time.time()
        if delay > 0:
            time.sleep(delay)
        index += 1
        taken = time.time() - start
        # 只截浮窗那一块，按拍照时最新的截图区域（设置窗口那几张的区域不一样）
        region = markers()[1]
        if not region:
            raise SystemExit("演示没有写出截图区域")
        left, top, width, height = screen_rect(region)
        path = os.path.join(work, f"{prefix}{index:02d}-{name}-{taken:.2f}s.png")
        subprocess.run(["screencapture", "-x", "-t", "png", f"-R{left},{top},{width},{height}", path], check=False)
        shots.append(path)
wait_for("end")

# 一次转好：长边缩到 640，存成 JPEG（每张单独调用 sips 要多花几分钟）
taken_shots = []
for path in shots:
    if os.path.exists(path):
        taken_shots.append(path)
    else:
        print(f"没有截到 {os.path.basename(path)}")
if shots and not taken_shots:
    raise SystemExit("一张都没有截到")
converted = os.path.join(work, f"{appearance}-jpeg")
os.makedirs(converted, exist_ok=True)
if taken_shots:
    subprocess.run(["sips", "-Z", "640", "-s", "format", "jpeg", "-s", "formatOptions", "72", *taken_shots, "--out", converted],
                   capture_output=True, check=True)
for path in taken_shots:
    base = os.path.basename(path)[:-4]
    # sips 存到文件夹里时沿用原来的文件名，扩展名统一换成 .jpg
    for candidate in (base + ".png", base + ".jpg", base + ".jpeg"):
        source = os.path.join(converted, candidate)
        if os.path.exists(source):
            os.replace(source, os.path.join(out, base + ".jpg"))
            break
    else:
        print(f"没有转好 {base}")
print(f"{appearance}：截图 {len(shots)} 张，存在 {out}")
PY
}

run_demo light "$SCALE" ""
# 深色外观再拍一组（动画放慢得少一些，只拍停下来之后的样子）；POP_SKIP_DARK=1 时跳过
if [ "${POP_SKIP_DARK:-0}" != "1" ]; then
  run_demo dark 2 "dark-"
fi

ls "$OUT"
pkill -x Pop 2>/dev/null || true
