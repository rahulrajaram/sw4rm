#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SDK_PATH = ROOT / "sdks/py_sdk"
TAG_PREFIX = "py-v"


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd or ROOT, check=True, text=True, capture_output=True)


def latest_prev_tag(current_tag: str) -> str | None:
    # Find the previous tag with same prefix
    out = run(["git", "tag", "--list", f"{TAG_PREFIX}*", "--sort=-creatordate"]).stdout.strip().splitlines()
    for t in out:
        if t == current_tag:
            continue
        return t
    return None


def collect_commits(since: str | None, until: str) -> list[tuple[str, str]]:
    rev = f"{since}..{until}" if since else until
    log = run(["git", "log", "--pretty=%H%x00%s", "--name-only", rev]).stdout
    lines = log.splitlines()
    commits = []
    i = 0
    while i < len(lines):
        if "\x00" in lines[i]:
            sha, subject = lines[i].split("\x00", 1)
            i += 1
            touched = []
            while i < len(lines) and lines[i] and "\x00" not in lines[i]:
                touched.append(lines[i])
                i += 1
            # Skip blank separator lines
            while i < len(lines) and lines[i] == "":
                i += 1
            if any(p.startswith("sdks/py_sdk/") for p in touched):
                commits.append((sha, subject))
        else:
            i += 1
    return commits


def categorize(subject: str) -> str:
    lowered = subject.lower()
    for k in ("feat", "fix", "perf", "refactor", "docs", "test", "build", "ci", "chore", "deps"):
        if lowered.startswith(k + ":") or lowered.startswith(k + "("):
            return k
    return "other"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME", ""))
    ap.add_argument("--since-tag", default="")
    args = ap.parse_args()

    tag = args.tag
    if not tag:
        print("Missing --tag or GITHUB_REF_NAME", file=sys.stderr)
        sys.exit(2)

    since = args.since_tag or latest_prev_tag(tag)
    commits = collect_commits(since, tag)

    print(f"# Python SDK {tag.removeprefix(TAG_PREFIX)} Release Notes\n")
    if since:
        print(f"Changes since {since}:\n")

    buckets = {}
    for _, subj in commits:
        buckets.setdefault(categorize(subj), []).append(subj)

    order = ["feat", "fix", "perf", "refactor", "docs", "test", "build", "ci", "chore", "deps", "other"]
    for k in order:
        if k in buckets:
            print(f"## {k.capitalize()}\n")
            for s in buckets[k]:
                print(f"- {s}")
            print()

    if not commits:
        print("No changes scoped to sdks/py_sdk in this range.")


if __name__ == "__main__":
    main()

