#!/usr/bin/env python3
"""稳定版按上海工作日每日最多一次；测试版按已验证的 main 提交发布。"""
import argparse
import datetime as dt
import json
import pathlib
import re
import sys

SHANGHAI = dt.timezone(dt.timedelta(hours=8))
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")


def first_heading(text):
    match = re.search(r"^##\s+(.+)$", text, re.M)
    if not match:
        raise ValueError("CHANGELOG.md 缺少顶部章节")
    return re.split(r"[（(]", match[1], maxsplit=1)[0].strip()


def stable_allowed(releases, now):
    today = now.astimezone(SHANGHAI).date()
    if today.weekday() >= 5:
        return False
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        published = release.get("published_at")
        if not published:
            return False
        day = dt.datetime.fromisoformat(published.replace("Z", "+00:00")).astimezone(SHANGHAI).date()
        if day == today:
            return False
    return True


def plan(changelog, marketing_version, releases, now, event, run_number):
    heading = first_heading(changelog)
    if heading not in ("未发布", "Unreleased") and not VERSION.fullmatch(heading):
        raise ValueError("顶部章节必须是未发布或正式版本号")
    if not VERSION.fullmatch(marketing_version):
        raise ValueError("MARKETING_VERSION 必须是正式版本号")
    if heading not in ("未发布", "Unreleased") and heading != marketing_version:
        raise ValueError("顶部版本与 MARKETING_VERSION 不一致")
    tags = {r["tag_name"] for r in releases}
    stable = heading if VERSION.fullmatch(heading) and "v" + heading not in tags and stable_allowed(releases, now) else ""
    beta = f"{marketing_version}-beta.{run_number}" if event == "push" else ""
    if beta and "v" + beta in tags:
        beta = ""
    return {"version": stable, "beta": beta}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("plan", "allowed"))
    parser.add_argument("--version")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--project", default="project.yml")
    parser.add_argument("--event", default="push")
    parser.add_argument("--run-number", type=int, default=0)
    args = parser.parse_args()
    raw = json.load(sys.stdin)
    releases = [r for page in raw for r in page] if raw and isinstance(raw[0], list) else raw
    now = dt.datetime.now(dt.timezone.utc)
    changelog = pathlib.Path(args.changelog).read_text()
    if args.mode == "allowed":
        if not args.version or first_heading(changelog) != args.version:
            raise ValueError("稳定版必须先把未发布章节改成对应版本号")
        print("allowed=" + str(stable_allowed(releases, now)).lower())
    else:
        project = pathlib.Path(args.project).read_text()
        match = re.search(r"^\s*MARKETING_VERSION:\s*[\"']?([0-9.]+)", project, re.M)
        if not match:
            raise ValueError("project.yml 缺少 MARKETING_VERSION")
        for key, value in plan(changelog, match[1], releases, now, args.event, args.run_number).items():
            print(f"{key}={value}")


if __name__ == "__main__":
    main()
