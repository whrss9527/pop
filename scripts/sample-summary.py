#!/usr/bin/env python3
"""把 sample 的报告缩成几行：主线程在忙（不是在等事件）的那些次里，最常走的调用路径、最常停在哪里、经过了 Pop 的哪些代码。

截图脚本（scripts/overlay-screenshots.sh）在主线程卡了 1 秒以上时用 sample 采样，再用这个脚本把报告缩短打进 CI 的日志。
最外层事件循环在等事件（__CFRunLoopServiceMachPort）的那些次不算：采样开始前后主线程空着的时候都在那里。

用法：scripts/sample-summary.py <sample 报告> [最多列几层，默认 30]
"""
import re
import sys
from collections import Counter

IDLE = "__CFRunLoopServiceMachPort"
RUN_LOOP = "__CFRunLoopRun"
WIDTH = 150


class Frame:
    def __init__(self, count, name, image):
        self.count = count
        self.name = name
        self.image = image
        self.children = []
        # 这一支里主线程空着（最外层事件循环在等事件）的次数
        self.idle = 0
        # 线程的根上记着线程那一行
        self.title = ""

    @property
    def busy(self):
        return self.count - self.idle

    def label(self):
        text = f"{self.name}  ({self.image})" if self.image else self.name
        return text if len(text) <= WIDTH else text[:WIDTH - 1] + "…"


def threads(lines):
    """调用图里的每个线程建成一棵树（根上记着线程那一行，比如「Thread_123   DispatchQueue_1: com.apple.main-thread  (serial)」）"""
    roots = []
    stack = []
    base = None
    in_graph = False
    for line in lines:
        if line.startswith("Call graph:"):
            in_graph = True
            continue
        if not in_graph:
            continue
        if not line.strip():
            if roots:
                break
            continue
        match = re.match(r"^( *[+!:| ]*?)(\d+) (.*)$", line)
        if not match:
            continue
        indent, count, rest = len(match.group(1)), int(match.group(2)), match.group(3)
        if base is None or indent <= base:
            base = indent
            root = Frame(count, "", "")
            root.title = rest.strip()
            roots.append(root)
            stack = [(indent, root)]
            continue
        symbol = re.match(r"^(.*?)\s+\(in ([^)]+)\)", rest)
        name, image = (symbol.group(1), symbol.group(2)) if symbol else (rest, "")
        frame = Frame(count, name.strip(), image.strip())
        while stack[-1][0] >= indent:
            stack.pop()
        stack[-1][1].children.append(frame)
        stack.append((indent, frame))
    return roots


def contains(frame, name):
    return frame.name == name or any(contains(child, name) for child in frame.children)


def main_thread(lines):
    """主线程：线程那一行写着 com.apple.main-thread 的；主线程正在同步等别的队列时写的是那个队列，这时认 NSApplicationMain"""
    roots = threads(lines)
    return (next((root for root in roots if "com.apple.main-thread" in root.title), None)
            or next((root for root in roots if contains(root, "NSApplicationMain")), None))


def mark_idle(frame, loops=0):
    """数出每一支里最外层事件循环在等事件的次数（里面再套的事件循环在等，是被别的事情拖住了，算忙）"""
    if frame.name == RUN_LOOP:
        loops += 1
    if frame.name == IDLE and loops == 1:
        frame.idle = frame.count
    else:
        frame.idle = sum(mark_idle(child, loops) for child in frame.children)
    return frame.idle


def own_samples(frame, counter):
    """每一层自己（不在更里面的调用里）忙的次数，按函数加起来"""
    inner = sum(child.count for child in frame.children)
    if frame.name and frame.count > inner:
        counter[frame.label()] += frame.count - inner
    for child in frame.children:
        if child.busy > 0:
            own_samples(child, counter)


def summarize(text, depth=30):
    root = main_thread(text.splitlines())
    if root is None:
        # 看看 sample 写了什么
        head = [line.strip() for line in text.splitlines() if line.strip()][:6]
        return ["报告里找不到主线程的调用图，报告开头："] + ["  " + line[:WIDTH] for line in head]
    mark_idle(root)
    lines = []
    if "com.apple.main-thread" not in root.title:
        lines.append(f"主线程这时在别的队列上：{root.title[:WIDTH]}")
    if root.busy <= 0:
        return lines + [f"采样 {root.count} 次，主线程都空着（开始采样时已经缓过来了）"]
    lines.append(f"采样 {root.count} 次，主线程在忙 {root.busy} 次")

    path = []
    frame = root
    while True:
        busy = [child for child in frame.children if child.busy > 0]
        if not busy:
            break
        frame = max(busy, key=lambda child: child.busy)
        path.append(frame)

    pop_frames = [f.name for f in path if f.image.startswith("Pop") and f.name != "main"]
    if pop_frames:
        lines.append("经过 Pop 的代码（从外到里）：" + " → ".join(pop_frames[-6:]))
    # 最外层事件循环外面那几层（start、NSApplicationMain……）每次都一样，不列
    loop = next((index for index, f in enumerate(path) if f.name == RUN_LOOP), None)
    if loop is not None and loop + 1 < len(path):
        path = path[loop + 1:]
    shown = path[-depth:]
    hidden = len(path) - len(shown)
    lines.append(f"最常走的路径（最里面 {len(shown)} 层" + (f"，外面还有 {hidden} 层" if hidden else "") + "，前面的数是忙的次数）：")
    lines.extend(f"  {f.busy:>5} {f.label()}" for f in shown)

    counter = Counter()
    own_samples(root, counter)
    top = [(label, count) for label, count in counter.most_common(6) if count * 20 >= root.busy]
    if top:
        lines.append("最常停在：")
        lines.extend(f"  {count:>5} {label}" for label, count in top)
    return lines


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("用法：scripts/sample-summary.py <sample 报告> [最多列几层]")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as report:
        content = report.read()
    for line in summarize(content, int(sys.argv[2]) if len(sys.argv) > 2 else 30):
        print(line)
