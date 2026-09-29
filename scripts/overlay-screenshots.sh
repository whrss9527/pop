#!/usr/bin/env bash
# 给浮窗拍一组截图：用演示模式启动 Pop（POP_DEMO=1，动画放慢 POP_ANIMATION_SCALE 倍），
# 按 Pop 写出的步骤时间在固定的时刻截屏，裁出浮窗那一块，存成 JPEG。
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
  open -n --env POP_DEMO=1 --env "POP_ANIMATION_SCALE=${scale}" --env "POP_DEMO_LOG=${log}" \
    --env "POP_APPEARANCE=${appearance}" "$APP"
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
    ("annotate", [1.5]),
    ("settings-plugins", [0.5]),
    ("settings-ai", [0.5]),
    ("settings-hotKeys", [0.5]),
]
if appearance == "dark":
    # 深色外观只拍停下来之后的样子
    plan = [("loaded", [2.6]), ("slide", [3.0]), ("commit", [5.0]), ("toast", [1.2]), ("chooser", [4.0]),
            ("drag-clipboard", [2.4]), ("release", [3.5]), ("unit", [3.0]), ("pin", [3.0]), ("ai", [3.0]),
            ("layout", [3.0]), ("translate", [3.0]), ("snippets", [3.0]), ("diff", [3.0]), ("palette", [3.0]),
            ("shelf", [3.0]), ("openWith", [3.0]), ("markdown", [3.0]), ("extract", [3.0]), ("jsonTypes", [3.0]),
            ("toMarkdown", [3.0]), ("regex", [3.0]), ("history", [3.0]), ("history-search", [3.0]),
            ("reminder", [3.0]), ("table", [3.0]), ("photo", [3.0]), ("annotate", [1.5]),
            ("settings-plugins", [0.5]), ("settings-ai", [0.5]), ("settings-hotKeys", [0.5])]
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

shots = []
index = 0
for name, offsets in plan:
    start, region = wait_for(name)
    for offset in offsets:
        target = start + offset * factor
        delay = target - time.time()
        if delay > 0:
            time.sleep(delay)
        index += 1
        taken = time.time() - start
        path = os.path.join(work, f"{prefix}{index:02d}-{name}-{taken:.2f}s.png")
        subprocess.run(["screencapture", "-x", "-t", "png", path], check=False)
        # 按拍照时最新的截图区域裁图（设置窗口那几张的区域不一样）
        shots.append((path, markers()[1]))
wait_for("end")

for path, region in shots:
    if not region:
        raise SystemExit("演示没有写出截图区域")
    x, y, w, h, screen_w, screen_h = region
    if not os.path.exists(path):
        print(f"没有截到 {os.path.basename(path)}")
        continue
    info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path], capture_output=True, text=True).stdout
    pixel_w = int(info.split("pixelWidth:")[1].split()[0])
    pixel_h = int(info.split("pixelHeight:")[1].split()[0])
    s = pixel_w / screen_w
    # AppKit 坐标 y 向上，图片 y 向下；超出屏幕的部分裁掉
    left = max(0, min(int(x * s), pixel_w - 1))
    top = max(0, min(int((screen_h - y - h) * s), pixel_h - 1))
    width = min(int(w * s), pixel_w - left)
    height = min(int(h * s), pixel_h - top)
    cropped = path[:-4] + "-crop.png"
    subprocess.run(["sips", "-c", str(height), str(width), "--cropOffset", str(top), str(left), path, "--out", cropped],
                   capture_output=True, check=True)
    name = os.path.basename(path)[:-4] + ".jpg"
    subprocess.run(["sips", "-Z", "640", "-s", "format", "jpeg", "-s", "formatOptions", "72", cropped,
                    "--out", os.path.join(out, name)], capture_output=True, check=True)
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
