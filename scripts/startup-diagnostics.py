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


def process_logs(pids, predicate='process == "Pop"', runner=subprocess.run):
    if not pids or any(type(pid) is not int or pid <= 0 for pid in pids):
        raise ValueError("启动日志需要明确的本次进程PID")
    # 系统日志的墙钟可能早于shell的date；回看日志后按实际PID过滤，旧进程不能使断言通过。
    result = runner(["log", "show", "--last", "10m", "--style", "json", "--predicate", predicate],
                    capture_output=True, text=True, timeout=15)
    if result.returncode != 0:
        raise RuntimeError("系统日志读取失败：" + result.stderr)
    records = json.loads(result.stdout)
    if not isinstance(records, list) or any(not isinstance(item, dict) for item in records):
        raise ValueError("系统日志JSON格式无效")
    if records and not any(type(item.get("processID")) is int for item in records):
        raise ValueError("系统日志缺少processID，不能确认本次进程")
    return [item for item in records if type(item.get("processID")) is int and item["processID"] in pids]


def render_logs(records):
    return "\n".join(f'{item.get("timestamp", "")} Pop[{item["processID"]}:{item.get("threadID", 0)}] '
                     f'[{item.get("subsystem", "")}:{item.get("category", "")}] {item.get("eventMessage", "")}'
                     for item in records)


def read_pids(path):
    pids = [int(value) for value in path.read_text().split()]
    if not pids or any(pid <= 0 for pid in pids):
        raise ValueError("本次启动PID记录为空或无效")
    return set(pids)


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


def collect(app, output, start, pids_file=None):
    output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1]
    commands = {
        "source": ["git", "rev-parse", "HEAD"],
        "system": ["sw_vers"],
        "architecture": ["uname", "-m"],
        "signature": ["codesign", "--display", "--verbose=4", str(app)],
        "bundle": ["plutil", "-p", str(app / "Contents/Info.plist")],
    }
    scoped = bool(pids_file and pids_file.is_file() and pids_file.read_text().strip())
    if scoped:
        commands["unified-log"] = ["python3", str(Path(__file__).resolve()), "logs", "--pids-file", str(pids_file),
                                   "--raw-json", str(output / "unified-log.json")]
    else:
        # 进程在捕获PID前已崩溃时仅保留未归属诊断；这些日志从不用于成功断言。
        commands["unified-log"] = ["log", "show", "--last", "10m", "--style", "compact", "--predicate", 'process == "Pop"']
    results = {name: capture(command, output / (name + ".txt"), cwd=root)
               for name, command in commands.items()}
    reports = Path.home() / "Library/Logs/DiagnosticReports"
    for report in reports.glob("Pop*"):
        if report.is_file():
            shutil.copyfile(report, output / report.name)
    metadata = {"commands": results, "primary_wall_start": start,
                "log_scope": "owned-pids" if scoped else "unscoped-no-captured-pids",
                "pid_scope": str(pids_file) if pids_file else None, "actions": {key: os.environ.get(key) for key in
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
    collect_args.add_argument("--pids-file", type=Path)
    log_args = commands.add_parser("logs")
    source = log_args.add_mutually_exclusive_group(required=True)
    source.add_argument("--pid", type=int)
    source.add_argument("--pids-file", type=Path)
    log_args.add_argument("--predicate", default='process == "Pop"')
    log_args.add_argument("--raw-json", type=Path)
    watch_args = commands.add_parser("watch")
    watch_args.add_argument("--hang-log", type=Path, required=True)
    watch_args.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "collect":
        collect(args.app, args.output, args.start, args.pids_file)
    elif args.command == "logs":
        pids = read_pids(args.pids_file) if args.pids_file else {args.pid}
        records = process_logs(pids, args.predicate)
        if args.raw_json:
            args.raw_json.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n")
        print(render_logs(records))
    else:
        watch(args.hang_log, args.output)


if __name__ == "__main__":
    main()
