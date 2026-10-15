#!/usr/bin/env python3
"""采集同一构建的配对渲染测量；数据采集完成不代表通过产品性能门槛。"""
import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

VARIANTS = ("baseline", "no-ghost", "legacy-glass")


def parse_demo(text, variant):
    rows = [line.split() for line in text.splitlines()]
    if [r for r in rows if r[:1] == ["renderProbe.variant"]] != [["renderProbe.variant", variant]]:
        raise ValueError("缺失、重复或错误的实验条件")
    names = ("focusSounds.start", "focusSounds", "emojiSymbols.start", "emojiSymbols", "renderProbe.end")
    markers = [r for r in rows if r and r[0] in names]
    if [r[0] for r in markers] != list(names) or any(len(r) != 3 for r in markers):
        raise ValueError("演示步骤缺失、重复或顺序错误")
    times = [float(r[1]) for r in markers]
    if any(not math.isfinite(t) or t < 0 for t in times) or any(a > b for a, b in zip(times, times[1:])):
        raise ValueError("演示时间倒退，不能关联采样")
    hangs = []
    for row in rows:
        if row[:1] != ["hang"]:
            continue
        if len(row) not in (3, 5) or (len(row) == 5 and row[3] != "paused"):
            raise ValueError("卡顿记录不完整")
        start, duration = map(float, row[1:3])
        paused = float(row[4]) if len(row) == 5 else 0
        if not math.isfinite(start) or start < 0 or not (0 <= duration < 120):
            raise ValueError("卡顿时长无效")
        if not math.isfinite(paused) or paused < 0:
            raise ValueError("进程暂停时长无效")
        hangs.append({"start": start, "duration": duration, "process_paused_seconds": paused})
    emoji = [r["duration"] for r in hangs if times[2] <= r["start"] <= times[-1]]
    maximum = max(emoji, default=0)
    return {"markers": dict(zip(names, times)), "hangs": hangs, "emoji_max_hang": maximum,
            "within_existing_two_second_limit": maximum <= 2}


def full_prefix_configuration():
    """Read only the original literal screenshot plan; never execute the shell/Python driver."""
    script = Path(__file__).with_name("overlay-screenshots.sh").read_text()
    source = script.split("<<'PY'\n", 1)[1].split("\nPY", 1)[0]
    plan = next(node.value for node in ast.parse(source).body
                if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "plan" for t in node.targets))
    quick = [name for name, offsets in ast.literal_eval(plan) if min(offsets) >= 3]
    fixture = Path(__file__).with_name("fixtures") / "emoji-full-prefix.json"
    return quick, json.loads(fixture.read_text())


def verify_full_prefix(text, appearance):
    _, fixture = full_prefix_configuration()
    actual, times = [], []
    for line in text.splitlines():
        row = line.split()
        if len(row) != 3 or row[0] in ("hang", "stall", "pid"):
            continue
        try:
            timestamp, scale = float(row[1]), float(row[2])
        except ValueError:
            continue
        if not math.isfinite(timestamp) or not math.isfinite(scale) or timestamp < 0 or scale <= 0:
            raise ValueError("完整前缀时间或动画倍数无效")
        actual.append([row[0], scale])
        times.append(timestamp)
        if row[0] == "emojiSymbols":
            break
    if actual != fixture["appearances"][appearance] or any(a > b for a, b in zip(times, times[1:])):
        raise ValueError("完整演示前缀缺失、顺序或动画倍数与原CI不符")
    if text.splitlines().count("renderProbe.workload full-prefix") != 1:
        raise ValueError("缺少完整演示负载标识")
    return len(actual)


def target_stalls(text):
    rows = text.splitlines()
    start = next((i for i, line in enumerate(rows) if line.startswith("emojiSymbols.start ")), None)
    if start is None:
        return []
    return [line for line in rows[start + 1:] if line.startswith("stall ")]


def stop_owned(process):
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            process.wait(timeout=5)
            return
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def measure(app, output, variant, appearance, diagnostic=False, workload="isolated"):
    output.mkdir(parents=True)
    demo = output / "demo.log"
    environment = dict(os.environ, POP_DEMO="1", POP_RENDER_PROBE="1", POP_RENDER_PROBE_VARIANT=variant,
                       POP_DEMO_LOG=str(demo), POP_APPEARANCE=appearance, POP_ANIMATION_SCALE="2",
                       POP_OVERLAY_DIAGNOSTICS_LOG=str(output / "overlay.jsonl"),
                       POP_PLUGIN_INDEX_URL=(Path(__file__).resolve().parents[1] / "plugins/index.json").as_uri(),
                       POP_PLUGIN_DIR=str(app.parent))
    if workload == "full-prefix":
        quick, _ = full_prefix_configuration()
        environment.update(POP_RENDER_PROBE_WORKLOAD=workload,
                           POP_ANIMATION_SCALE="6" if appearance == "light" else "2",
                           POP_DEMO_QUICK_STEPS=",".join(quick))
    else:
        environment["POP_RENDER_PROBE_WORKLOAD"] = "isolated"
    deadline = 900 if workload == "full-prefix" else 60
    result = {"variant": variant, "appearance": appearance, "workload": workload, "kind": "diagnostic" if diagnostic else "measurement"}
    samplers, seen = [], set()
    with (output / "stdout.log").open("w") as stdout, (output / "stderr.log").open("w") as stderr:
        process = subprocess.Popen([str(app / "Contents/MacOS/Pop")], env=environment,
                                   stdout=stdout, stderr=stderr, start_new_session=True)
        result["pid"] = process.pid
        began = time.monotonic()
        try:
            while process.poll() is None:
                if time.monotonic() - began > deadline:
                    raise TimeoutError(f"渲染诊断在{deadline}秒内未结束")
                if diagnostic and demo.exists() and len(samplers) < 3 and all(p.poll() is not None for p in samplers):
                    stalls = target_stalls(demo.read_text())
                    fresh = [line for line in stalls if line not in seen]
                    if fresh:
                        seen.update(fresh)
                        index = len(samplers)
                        # 独立诊断重复才采样；所有用于比较的原测量均不采样。
                        samplers.append(subprocess.Popen(["/usr/bin/sample", str(process.pid), "1", "10", "-file",
                                                          str(output / f"sample-{index}.txt")],
                                                         stdout=stderr, stderr=stderr))
                time.sleep(0.1)
            result["exit_code"] = process.returncode
            if process.returncode != 0:
                raise RuntimeError("诊断进程异常退出")
            text = demo.read_text()
            result.update(parse_demo(text, variant))
            if workload == "full-prefix":
                result["verified_prefix_steps"] = verify_full_prefix(text, appearance)
            if not (output / "overlay.jsonl").is_file():
                raise ValueError("缺少窗口原始事件")
            events = [json.loads(line) for line in (output / "overlay.jsonl").read_text().splitlines()]
            ghosts = sum(e.get("event") == "ghostCreated" for e in events)
            if (variant == "no-ghost" and ghosts != 0) or (variant != "no-ghost" and ghosts == 0):
                raise ValueError("窗口事件不符合实验条件")
            result["ghosts_created"] = ghosts
        except Exception as error:
            result["error"] = str(error)
            raise
        finally:
            stop_owned(process)
            for sampler in samplers:
                try:
                    sampler.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    sampler.kill()
                    sampler.wait()
            result["sample_exit_codes"] = [p.returncode for p in samplers]
            result["elapsed_monotonic"] = time.monotonic() - began
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--workload", choices=("isolated", "full-prefix"), default="isolated")
    parser.add_argument("--cycles", type=int, choices=(1, 2, 3))
    args = parser.parse_args()
    cycles = args.cycles if args.cycles is not None else (1 if args.workload == "full-prefix" else 3)
    if sys.platform != "darwin":
        parser.error("需要真实macOS图形会话")
    app, output = args.app.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    metadata = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "system": subprocess.check_output(["sw_vers"], text=True),
                "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True),
                "executable_sha256": hashlib.sha256((app / "Contents/MacOS/Pop").read_bytes()).hexdigest(),
                "workload": args.workload, "cycles": cycles,
                "screenshot_readback": False,
                "acceptance": "diagnostic measurements only; regular CI retains its original two-second gate"}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    results = []
    try:
        for appearance in ("light", "dark"):
            for cycle in range(cycles):
                order = VARIANTS[cycle:] + VARIANTS[:cycle]
                for variant in order:
                    folder = output / f"{len(results):02d}-{appearance}-{variant}"
                    results.append(measure(app, folder, variant, appearance, workload=args.workload))
        # 每个条件至多一次另行诊断；保留所有失败测量，诊断不替换它们。
        for variant in VARIANTS:
            failed = next((r for r in results if r["variant"] == variant and not r["within_existing_two_second_limit"]), None)
            if failed:
                measure(app, output / f"diagnostic-{variant}", variant, failed["appearance"], diagnostic=True, workload=args.workload)
    finally:
        (output / "measurements.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
