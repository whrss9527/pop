#!/usr/bin/env python3
"""保留启动原始证据；采样仅用于失败后的独立诊断启动，不参与首次门禁计时。"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import time


def capture(command, destination, timeout=15, cwd=None):
    result = {"command": command}
    with destination.open("w") as output:
        try:
            process = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                     timeout=timeout, cwd=cwd)
            result["exit_code"] = process.returncode
        except subprocess.TimeoutExpired:
            result["timed_out"] = True
        except OSError as error:
            result["error"] = str(error)
    return result


def collect(app, output, start):
    output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    commands = {
        "source": ["git", "rev-parse", "HEAD"],
        "system": ["sw_vers"],
        "architecture": ["uname", "-m"],
        "signature": ["codesign", "--display", "--verbose=4", str(app)],
        "bundle": ["plutil", "-p", str(app / "Contents/Info.plist")],
        "unified-log": ["log", "show", "--start", start, "--style", "compact",
                        "--predicate", 'process == "Pop"'],
    }
    results = {name: capture(command, output / (name + ".txt"), cwd=root)
               for name, command in commands.items()}
    reports = Path.home() / "Library/Logs/DiagnosticReports"
    for report in reports.glob("Pop*"):
        if report.is_file():
            shutil.copyfile(report, output / report.name)
    metadata = {"commands": results, "actions": {key: os.environ.get(key) for key in
                ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "RUNNER_OS", "RUNNER_ARCH")}}
    (output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")


def watch(hang_log, output, duration=12, sample_tool="/usr/bin/sample", pid_command=None):
    """一次只采一个，最多三次；工具超时/权限错误原样记录，不改变首次启动结果。"""
    output.mkdir(parents=True, exist_ok=True)
    stopped = False

    def stop(signum, frame):
        nonlocal stopped
        stopped = True

    previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGTERM, signal.SIGINT)}
    deadline = time.monotonic() + duration
    seen, results, pid = set(), [], None
    try:
        while not stopped and time.monotonic() < deadline:
            if pid is None:
                try:
                    candidate = subprocess.run(pid_command or ["pgrep", "-nx", "Pop"],
                                               capture_output=True, text=True, timeout=1).stdout.strip()
                    if candidate.isdecimal():
                        pid = candidate
                        (output / "pid.txt").write_text(pid + "\n")
                except (OSError, subprocess.TimeoutExpired):
                    pass
            lines = hang_log.read_text(errors="replace").splitlines() if hang_log.exists() else []
            for line in lines:
                parts = line.split()
                if (len(parts) < 2 or parts[0] != "stall" or
                        not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", parts[1]) or parts[1] in seen):
                    continue
                if not pid:
                    continue
                stamp = parts[1]
                seen.add(stamp)
                if len(results) >= 3 or stopped or time.monotonic() >= deadline:
                    continue
                command = [sample_tool, pid, "3", "10", "-mayDie", "-file", str(output / (stamp + ".txt"))]
                if Path("/usr/sbin/taskpolicy").is_file():
                    command = ["/usr/sbin/taskpolicy", "-c", "utility"] + command
                result = capture(command, output / (stamp + ".log"),
                                 timeout=min(8, max(0.1, deadline - time.monotonic())))
                result["stall"] = stamp
                results.append(result)
            time.sleep(0.05)
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        (output / "samples.json").write_text(json.dumps(results, indent=2) + "\n")
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    collect_args = commands.add_parser("collect")
    collect_args.add_argument("--app", type=Path, required=True)
    collect_args.add_argument("--output", type=Path, required=True)
    collect_args.add_argument("--start", required=True)
    watch_args = commands.add_parser("watch")
    watch_args.add_argument("--hang-log", type=Path, required=True)
    watch_args.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "collect":
        collect(args.app, args.output, args.start)
    else:
        watch(args.hang_log, args.output)


if __name__ == "__main__":
    main()
