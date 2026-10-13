#!/usr/bin/env python3
"""在截图测量之前收环境，退出后保存原始诊断；不改性能判定。"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import shutil
import subprocess


ENVIRONMENT_KEYS = (
    "GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_RUN_NUMBER",
    "GITHUB_WORKFLOW", "GITHUB_JOB", "GITHUB_REF", "GITHUB_EVENT_NAME",
    "RUNNER_NAME", "RUNNER_OS", "RUNNER_ARCH", "ImageOS", "ImageVersion",
)
RAW_FILES = (
    "demo-light.log", "demo-dark.log", "overlay-light.jsonl", "overlay-dark.jsonl",
    "hangs.txt", "stalls.txt",
)


def command_result(arguments, timeout=20):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        return {"command": arguments, "status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"command": arguments, "unavailable": type(error).__name__}


def collect_environment(output, environment=None):
    environment = os.environ if environment is None else environment
    output.mkdir(parents=True, exist_ok=True)
    commands = {
        "system": ["/usr/bin/sw_vers"],
        "architecture": ["/usr/bin/uname", "-m"],
        "xcode": ["/usr/bin/xcodebuild", "-version"],
        "displays": ["/usr/sbin/system_profiler", "SPDisplaysDataType", "-json"],
    }
    data = {
        "collected_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "github": {key: environment[key] for key in ENVIRONMENT_KEYS if key in environment},
        "commands": {key: command_result(arguments) for key, arguments in commands.items()},
    }
    if "GITHUB_SHA" not in data["github"]:
        repository = pathlib.Path(__file__).resolve().parent.parent
        data["source"] = command_result(["git", "-C", str(repository), "rev-parse", "HEAD"])
    (output / "environment.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def preserve(work, output, exit_status):
    output.mkdir(parents=True, exist_ok=True)
    candidates = [work / name for name in RAW_FILES]
    for appearance in ("light", "dark"):
        folder = work / ("samples-" + appearance)
        if folder.is_dir() and not folder.is_symlink():
            candidates.extend(folder.glob("*.txt"))
            candidates.extend(folder.glob("*.log"))
    copied = []
    for source in sorted(candidates):
        if source.is_symlink() or not source.is_file():
            continue
        relative = source.relative_to(work)
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        copied.append({"file": str(relative), "bytes": destination.stat().st_size,
                       "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
    result = {"screenshot_exit_status": exit_status, "files": copied}
    (output / "manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    environment = commands.add_parser("environment")
    environment.add_argument("--output", type=pathlib.Path, required=True)
    saved = commands.add_parser("preserve")
    saved.add_argument("--work", type=pathlib.Path, required=True)
    saved.add_argument("--output", type=pathlib.Path, required=True)
    saved.add_argument("--exit-status", type=int, required=True)
    args = parser.parse_args()
    if args.command == "environment":
        collect_environment(args.output)
    else:
        preserve(args.work, args.output, args.exit_status)


if __name__ == "__main__":
    main()
