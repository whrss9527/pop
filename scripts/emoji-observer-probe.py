#!/usr/bin/env python3
"""Collect the original screenshot driver's readback × sampling controls, preserving failed gates."""
import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import signal
import subprocess
import sys

spec = importlib.util.spec_from_file_location("render_probe", Path(__file__).with_name("emoji-render-probe.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

CONDITIONS = (("both", True, True), ("readback-only", True, False),
              ("sampling-only", False, True), ("neither", False, False))


def stop_app(app):
    executable = str(app / "Contents/MacOS/Pop")
    processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
    for row in processes.splitlines():
        fields = row.strip().split(None, 1)
        if len(fields) == 2 and fields[1] == executable:
            try:
                os.kill(int(fields[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass


def run_condition(app, output, name, readback, sampling):
    output.mkdir()
    env = dict(os.environ, POP_OBSERVER_PROBE="1", POP_OBSERVER_READBACK=str(int(readback)),
               POP_OBSERVER_SAMPLING=str(int(sampling)), POP_SKIP_DARK="0", POP_HANG_LIMIT="2")
    result = {"condition": name, "readback": readback, "sampling": sampling, "launch_method": "LaunchServices open"}
    process = None
    try:
        with (output / "driver.log").open("w") as log:
            process = subprocess.Popen([str(Path(__file__).with_name("overlay-screenshots.sh")), str(app), str(output), "6"],
                                       env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            result["driver_exit_code"] = process.wait(timeout=1200)
        if process.returncode not in (0, 1):
            raise ValueError("原截图驱动异常退出")
        rows = []
        for appearance in ("light", "dark"):
            text = (output / "diagnostics" / f"demo-{appearance}.log").read_text()
            row = probe.parse_demo(text, "baseline")
            row["verified_prefix_steps"] = probe.verify_full_prefix(text, appearance)
            row["appearance"] = appearance
            events = [json.loads(line) for line in (output / "diagnostics" / f"overlay-{appearance}.jsonl").read_text().splitlines()]
            if not any(e.get("event") == "ghostCreated" for e in events):
                raise ValueError("baseline缺少原窗口退场事件")
            row["sample_reports"] = len(list((output / "diagnostics" / f"samples-{appearance}").glob("*.txt")))
            if not sampling and row["sample_reports"] != 0:
                raise ValueError("关闭采样的条件仍有采样")
            rows.append(row)
        images = list(output.glob("*.jpg"))
        reported = re.findall(r"^(light|dark)：截图 ([0-9]+) 张", (output / "driver.log").read_text(), re.MULTILINE)
        if len(reported) != 2 or {row[0] for row in reported} != {"light", "dark"}:
            raise ValueError("缺少原驱动的完整图片计数")
        for appearance, count in reported:
            actual = sum(path.name.startswith("dark-") == (appearance == "dark") for path in images)
            if actual != int(count) or (readback and actual == 0) or (not readback and actual != 0):
                raise ValueError("图片读回条件或部分图片输出不符")
        for path in images:
            with path.open("rb") as file:
                if file.read(3) != b"\xff\xd8\xff":
                    raise ValueError("截图不是有效JPEG输出")
        failed_gate = any(hang["duration"] >= 2 for row in rows for hang in row["hangs"])
        if failed_gate != (process.returncode == 1):
            raise ValueError("驱动退出与原两秒门禁不符，不能视作完整采集")
        result.update(appearances=rows, image_count=len(images), original_performance_gate_failed=failed_gate)
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
        try:
            stop_app(app)
        except Exception as error:
            result["cleanup_error"] = str(error)
            raise
        finally:
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cycles", type=int, choices=(1,), default=1)
    args = parser.parse_args()
    if sys.platform != "darwin" or os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        parser.error("只在临时托管Mac执行，不接触个人App进程")
    if subprocess.run(["pgrep", "-x", "Pop"], capture_output=True).returncode == 0:
        parser.error("已有非本实验Pop进程，停止")
    app, output = args.app.resolve(), args.output.resolve()
    output.mkdir(exist_ok=False, parents=True)
    metadata = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
                "system": subprocess.check_output(["sw_vers"], text=True),
                "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True),
                "executable_sha256": hashlib.sha256((app / "Contents/MacOS/Pop").read_bytes()).hexdigest(),
                "workload": "original screenshot driver prefix; four readback/sampling conditions",
                "acceptance": "collection only; all original gate exit codes and failures retained"}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    results = []
    try:
        for name, readback, sampling in CONDITIONS:
            results.append(run_condition(app, output / name, name, readback, sampling))
    finally:
        (output / "measurements.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
