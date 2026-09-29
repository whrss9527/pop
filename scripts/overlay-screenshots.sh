#!/usr/bin/env bash
# 给浮窗拍一组截图：用演示模式启动 Pop（POP_DEMO=1，动画放慢 POP_ANIMATION_SCALE 倍），
# 按 Pop 写出的步骤时间在固定的时刻截屏，裁出浮窗那一块，存成 JPEG。
# 圆盘展开、指向、滑动、选中、结果卡片、提示、列表、取消都会拍到，包括动画的中间帧。
#
# 用法：scripts/overlay-screenshots.sh <Pop.app> <输出目录> [动画放慢倍数，默认 6]
set -euo pipefail

APP="${1:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
OUT="${2:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
SCALE="${3:-6}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d -t pop-screenshots)"
LOG="$WORK/demo.log"

pkill -x Pop 2>/dev/null || true
for _ in $(seq 1 20); do
  pgrep -x Pop > /dev/null || break
  sleep 0.5
done

open -n --env POP_DEMO=1 --env "POP_ANIMATION_SCALE=${SCALE}" --env "POP_DEMO_LOG=${LOG}" "$APP"

python3 - "$LOG" "$WORK" "$OUT" "$SCALE" <<'PY'
import os, subprocess, sys, time

log_path, work, out, scale = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])

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
]
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
        path = os.path.join(work, f"{index:02d}-{name}-{taken:.2f}s.png")
        subprocess.run(["screencapture", "-x", "-t", "png", path], check=False)
        shots.append(path)
wait_for("end")
_, region = markers()
if not region:
    raise SystemExit("演示没有写出截图区域")

x, y, w, h, screen_w, screen_h = region
for path in shots:
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
print(f"截图 {len(shots)} 张，存在 {out}")
PY

ls "$OUT"
pkill -x Pop 2>/dev/null || true
