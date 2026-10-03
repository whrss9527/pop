#!/usr/bin/env bash
# 给浮窗拍一组截图：用演示模式启动 Pop（POP_DEMO=1，动画放慢 POP_ANIMATION_SCALE 倍），
# 按 Pop 写出的步骤时间在固定的时刻截下浮窗那一块，最后一起转成 JPEG。
# 圆盘展开、指向、滑动、选中、结果卡片、提示、列表、取消、贴图、常用短语、文本对比、图片配色、暂存架、打开方式、
# Markdown 预览、截图标注都会拍到，包括动画的中间帧。
# 之后用深色外观再拍一组停下来之后的样子（文件名以 dark- 开头），POP_SKIP_DARK=1 时不拍。
# 只拍停下来之后的样子的插件包步骤不用放慢那么多：Pop 在这些步骤上按 2 倍走（POP_DEMO_QUICK_STEPS），省下时间。
# 两遍演示里主线程卡住超过 0.25 秒的地方最后都列出来，卡了 2 秒以上（POP_HANG_LIMIT）的算失败。
# 卡了半秒还没缓过来时（Pop 写一行 stall）用 sample 采样主线程，最后把卡了 1 秒以上的那几次在忙什么（scripts/sample-summary.py 缩短的）一起列出来。
#
# 用法：scripts/overlay-screenshots.sh <Pop.app> <输出目录> [动画放慢倍数，默认 6]
set -euo pipefail

APP="${1:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
OUT="${2:?用法: scripts/overlay-screenshots.sh <Pop.app> <输出目录> [倍数]}"
SCALE="${3:-6}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
WORK="$(mktemp -d -t pop-screenshots)"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
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
  python3 - "$log" "$WORK" "$OUT" "$scale" "$appearance" "$prefix" "$APP" "$PLUGIN_INDEX" "$SCRIPTS" <<'PY'
import os, shutil, subprocess, sys, threading, time

log_path, work, out, scale_text, appearance, prefix, app, plugin_index, scripts = sys.argv[1:10]
scale = float(scale_text)

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
    ("diskSpeed", [3.0]),
    ("worldTime", [3.0]),
    ("chart", [3.0]),
    ("focusSounds", [3.0]),
    ("emojiSymbols", [3.0]),
    ("bluetooth", [3.0]),
    ("calendar", [3.0]),
    ("breakReminder", [3.0]),
    ("breakReminder-banner", [3.0]),
    ("windowPiP", [3.0]),
    ("windowPiP-panel", [3.0]),
    ("mouseWheel", [3.0]),
    ("holdToQuit", [3.0]),
    ("holdToQuit-prompt", [3.0]),
    ("sleepTimer", [3.0]),
    ("sleepTimer-banner", [3.0]),
    ("sleepTimer-setup", [3.0]),
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
    ("settings-ring", [0.5]),
    ("settings-plugins", [0.5]),
    ("settings-ai", [0.5]),
    ("settings-hotKeys", [0.5]),
    ("settings-pluginLibrary", [0.8]),
]
# 每一张都在第 3 秒以后拍的步骤只拍停下来之后的样子
quick = [name for name, offsets in plan if min(offsets) >= 3.0]
if appearance == "dark":
    # 深色外观只拍停下来之后的样子
    plan = [("loaded", [2.6]), ("slide", [3.0]), ("commit", [5.0]), ("toast", [1.2]), ("chooser", [4.0]),
            ("drag-clipboard", [2.4]), ("release", [3.5]), ("unit", [3.0]), ("pin", [3.0]), ("ai", [3.0]),
            ("layout", [3.0]), ("translate", [3.0]), ("translate-compare", [3.0]), ("snippets", [3.0]), ("diff", [3.0]), ("palette", [3.0]),
            ("shelf", [3.0]), ("openWith", [3.0]), ("markdown", [3.0]), ("extract", [3.0]), ("jsonTypes", [3.0]),
            ("toMarkdown", [3.0]), ("regex", [3.0]), ("longText", [3.0]), ("longJSON", [3.0]), ("history", [3.0]), ("history-search", [3.0]),
            ("reminder", [3.0]), ("table", [3.0]), ("photo", [3.0]), ("rename", [3.0]), ("sql", [3.0]), ("vocabulary", [3.0]),
            ("duplicates", [3.0]), ("pdfPages", [3.0]), ("diskUsage", [3.0]), ("tidyFolder", [3.0]), ("uninstallApp", [3.0]), ("newFile", [3.0]), ("fileEncoding", [3.0]), ("appInfo", [3.0]), ("similarPhotos", [3.0]), ("mediaInfo", [3.0]), ("subtitles", [3.0]), ("fontPreview", [3.0]), ("encryptFiles", [3.0]), ("batteryInfo", [3.0]), ("voiceRecorder", [3.0]), ("systemInfo", [3.0]), ("soundDevices", [3.0]), ("resolution", [3.0]), ("diskSpeed", [3.0]), ("worldTime", [3.0]), ("chart", [3.0]), ("focusSounds", [3.0]), ("emojiSymbols", [3.0]), ("bluetooth", [3.0]), ("calendar", [3.0]), ("breakReminder", [3.0]), ("breakReminder-banner", [3.0]), ("windowPiP", [3.0]), ("windowPiP-panel", [3.0]), ("mouseWheel", [3.0]), ("holdToQuit", [3.0]), ("holdToQuit-prompt", [3.0]), ("sleepTimer", [3.0]), ("sleepTimer-banner", [3.0]), ("sleepTimer-setup", [3.0]), ("pdfPassword", [3.0]),
            ("toolbar", [1.2]), ("watermark", [3.0]), ("sendToPhone", [3.0]), ("idNumber", [3.0]), ("transcribe", [3.0]),
            ("idPhoto", [3.0]), ("webCapture", [3.0]), ("cropImage", [3.0]), ("beautify", [3.0]), ("compareImages", [3.0]), ("splitImage", [3.0]), ("appIcon", [3.0]),
            ("screenRecord-picker", [1.0]), ("screenRecord-countdown", [0.5]), ("screenRecord-recording", [0.6]), ("screenRecord", [3.0]), ("systemActions", [3.0]), ("textImage", [3.0]),
            ("menuShortcuts", [3.0]), ("quitApps", [3.0]), ("scrollCapture", [3.0]), ("screenPen", [3.0]), ("cameraBubble", [3.0]), ("pointerHighlight", [1.5]), ("teleprompter", [1.0]), ("spotlight", [1.0]), ("zoom", [1.0]), ("annotate", [1.5]),
            ("settings-ring", [0.5]), ("settings-plugins", [0.5]), ("settings-ai", [0.5]), ("settings-hotKeys", [0.5]),
            ("settings-pluginLibrary", [0.8])]

samples = os.path.join(work, f"samples-{appearance}")
os.makedirs(samples, exist_ok=True)
stop_sampling = threading.Event()

def sample_stalls():
    """Pop 写了 stall 行（主线程卡了半秒还没缓过来）就用 sample 采样 3 秒：一次只采一个，每遍最多 16 个。
    GitHub 的 runner 上用 sudo（不用输密码），本机 sudo 要密码时直接采（Pop 是同一个用户开的）"""
    use_sudo = shutil.which("sudo") is not None and subprocess.run(["sudo", "-n", "true"], capture_output=True).returncode == 0
    seen, running, taken = set(), None, 0
    while not stop_sampling.is_set():
        if running and running.poll() is not None:
            running = None
        lines = open(log_path, encoding="utf-8").read().splitlines() if os.path.exists(log_path) else []
        for line in lines:
            parts = line.split()
            if len(parts) < 2 or parts[0] != "stall" or parts[1] in seen:
                continue
            seen.add(parts[1])
            if running or taken >= 16:
                continue
            pid = subprocess.run(["pgrep", "-nx", "Pop"], capture_output=True, text=True).stdout.strip()
            if not pid:
                continue
            base = os.path.join(samples, parts[1])
            command = ["/usr/bin/sample", pid, "3", "10", "-mayDie", "-file", base + ".txt"]
            with open(base + ".log", "w") as output:
                running = subprocess.Popen((["sudo", "-n"] if use_sudo else []) + command, stdout=output, stderr=subprocess.STDOUT)
            taken += 1
        time.sleep(0.05)
    if running:
        try:
            running.wait(timeout=60)
        except subprocess.TimeoutExpired:
            running.terminate()

sampler = threading.Thread(target=sample_stalls, daemon=True)
sampler.start()

# Pop.app 旁边的插件包一起装载，演示里也有插件包的步骤
subprocess.run(["open", "-n", "--env", "POP_DEMO=1", "--env", f"POP_ANIMATION_SCALE={scale_text}",
                "--env", f"POP_DEMO_LOG={log_path}", "--env", f"POP_APPEARANCE={appearance}",
                "--env", f"POP_PLUGIN_INDEX_URL={plugin_index}", "--env", f"POP_PLUGIN_DIR={os.path.dirname(os.path.abspath(app))}",
                "--env", "POP_DEMO_QUICK_STEPS=" + ",".join(quick), app], check=True)

def markers():
    """每一步开始的时间和这一步的动画放慢倍数（Pop 在步骤那一行里写着；没写时就是启动时给的倍数），以及最新的截图区域"""
    result = {}
    region = None
    if os.path.exists(log_path):
        for line in open(log_path, encoding="utf-8").read().splitlines():
            parts = line.split()
            if not parts:
                continue
            if parts[0] == "region" and len(parts) >= 7:
                region = [int(p) for p in parts[1:7]]
            elif parts[0] in ("hang", "stall"):
                continue
            elif len(parts) >= 2:
                result[parts[0]] = (float(parts[1]), float(parts[2]) if len(parts) >= 3 else scale)
    return result, region

def wait_for(name, timeout=120):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found, _ = markers()
        if name in found:
            return found[name]
        time.sleep(0.03)
    # Pop 卡死了的话，采到的样最有用：先打出来
    for line in stall_report():
        print(line)
    raise SystemExit(f"等不到演示步骤 {name}，Pop 可能没有启动或者卡死了")

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
    start, step_scale = wait_for(name)
    for offset in offsets:
        target = start + offset * step_scale / 6.0
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
def hang_lines():
    """主线程卡住的地方（Pop 里 HangWatchdog 写的 hang 行）：「外观 秒数 在哪两步之间」，和每次卡了几秒（按开始的时间）"""
    found, _ = markers()
    steps = sorted((start, name) for name, (start, _) in found.items())

    def place(start):
        before = [name for at, name in steps if at <= start]
        after = [name for at, name in steps if at > start]
        return f"{before[-1] if before else '启动'} → {after[0] if after else '结束'}"

    hangs, lasted = [], {}
    for line in open(log_path, encoding="utf-8").read().splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "hang":
            lasted[parts[1]] = float(parts[2])
            # Pop 整个被停住的那段（采样的工具接上时）已经扣掉了，写出来扣了多少
            paused = f"（Pop 被停住 {float(parts[4]):.2f} 秒，没算进去）" if len(parts) >= 5 and parts[3] == "paused" else ""
            hangs.append(f"{appearance} {float(parts[2]):.2f} {place(float(parts[1]))}{paused}")
    return hangs, lasted, place

def stall_report():
    """等采样做完，把卡了 1 秒以上（或者还没缓过来）的那几次采到的样缩短（stall 行和 hang 行记的是同一个开始时间）"""
    stop_sampling.set()
    sampler.join(timeout=90)
    _, lasted, place = hang_lines()
    summaries = []
    for name in sorted(os.listdir(samples)):
        if not name.endswith(".log"):
            continue
        stamp = name[:-4]
        if lasted.get(stamp, 99) < 1.0:
            continue
        seconds = f"{lasted[stamp]:.2f}" if stamp in lasted else "?"
        summaries.append(f"{appearance} {seconds} 秒 {place(float(stamp))}：")
        report = os.path.join(samples, stamp + ".txt")
        if os.path.exists(report):
            result = subprocess.run([sys.executable, os.path.join(scripts, "sample-summary.py"), report], capture_output=True, text=True)
            lines = (result.stdout or result.stderr).splitlines()
        else:
            # sample 自己说了什么（权限不够、Pop 已经退出……）
            said = open(os.path.join(samples, name), errors="replace").read().strip().splitlines()
            lines = ["没有采到：" + (" / ".join(said[-3:]) if said else "sample 什么也没说")]
        summaries.extend("  " + line for line in lines)
    return summaries

wait_for("end")

# 卡住的地方和采到的样记进 hangs.txt、stalls.txt，两遍都拍完以后一起看
hangs, _, _ = hang_lines()
with open(os.path.join(work, "hangs.txt"), "a", encoding="utf-8") as f:
    f.writelines(line + "\n" for line in hangs)
print(f"{appearance}：主线程卡住超过 0.25 秒 {len(hangs)} 次")
summaries = stall_report()
if summaries:
    with open(os.path.join(work, "stalls.txt"), "a", encoding="utf-8") as f:
        f.writelines(line + "\n" for line in summaries)

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

# 主线程卡住的地方都列出来（外观、卡了几秒、在哪两步之间）；卡了 POP_HANG_LIMIT 秒（默认 2 秒）以上的算失败。
# 截图照样都拍完、转好，后面的步骤可以照常把它们传上去
HANG_LIMIT="${POP_HANG_LIMIT:-2}"
if [ -s "$WORK/hangs.txt" ]; then
  echo "主线程卡住超过 0.25 秒的地方（外观 秒数 在哪两步之间）："
  sort -k2,2 -n -r "$WORK/hangs.txt"
  if [ -s "$WORK/stalls.txt" ]; then
    echo
    echo "卡了 1 秒以上时主线程在做什么（sample 采样，主线程空着等事件的那些次不算）："
    cat "$WORK/stalls.txt"
  fi
  if awk -v limit="$HANG_LIMIT" '$2 + 0 >= limit + 0 { bad = 1 } END { exit bad ? 0 : 1 }' "$WORK/hangs.txt"; then
    echo "❌ 主线程卡了 ${HANG_LIMIT} 秒以上：用的时候会觉得 Pop 卡死了"
    exit 1
  fi
else
  echo "主线程没有卡住超过 0.25 秒的时候"
fi
