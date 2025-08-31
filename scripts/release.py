#!/usr/bin/env python3
import argparse
import subprocess
import sys
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]

SPEC_FILE = ROOT / "documentation/protocol/spec.md"
PYPROJECT = ROOT / "pyproject.toml"
PKG_JSON = ROOT / "sdks/js_sdk/package.json"
CARGO = ROOT / "sdks/rust_sdk/Cargo.toml"

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def die(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(1)


def read_spec_version() -> str:
    text = SPEC_FILE.read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r"^Version:\s*([0-9]+\.[0-9]+\.[0-9]+)", line.strip())
        if m:
            return m.group(1)
    die("Could not find spec version in spec.md")


def read_py_version() -> str:
    text = PYPROJECT.read_text(encoding="utf-8")
    in_project = False
    for line in text.splitlines():
        if line.strip().startswith("[project]"):
            in_project = True
            continue
        if in_project and line.strip().startswith("["):
            in_project = False
        if in_project:
            m = re.match(r"version\s*=\s*\"([^\"]+)\"", line.strip())
            if m:
                return m.group(1)
    die("Could not find Python version in pyproject.toml")


def read_js_version() -> str:
    return json.loads(PKG_JSON.read_text(encoding="utf-8"))["version"]


def read_rs_version() -> str:
    text = CARGO.read_text(encoding="utf-8")
    in_pkg = False
    for line in text.splitlines():
        if line.strip().startswith("[package]"):
            in_pkg = True
            continue
        if in_pkg and line.strip().startswith("["):
            in_pkg = False
        if in_pkg:
            m = re.match(r"version\s*=\s*\"([^\"]+)\"", line.strip())
            if m:
                return m.group(1)
    die("Could not find Rust version in Cargo.toml")


def ensure_versions_equal(expected: str):
    spec = read_spec_version()
    py = read_py_version()
    js = read_js_version()
    rs = read_rs_version()
    if not (spec == py == js == rs == expected):
        die(f"Version mismatch. expected={expected} spec={spec} py={py} js={js} rs={rs}")


def create_tag(tag: str, push: bool):
    subprocess.run(["git", "tag", tag], check=True)
    print(f"Created tag {tag}")
    if push:
        subprocess.run(["git", "push", "origin", tag], check=True)
        print(f"Pushed tag {tag}")


def main():
    ap = argparse.ArgumentParser(description="Create release tag for one SDK")
    ap.add_argument("target", choices=["py", "npm", "rs"], help="Which SDK to tag")
    ap.add_argument("version", help="SemVer X.Y.Z")
    ap.add_argument("--push", action="store_true", help="Push the created tag to origin")
    args = ap.parse_args()

    if not SEMVER_RE.match(args.version):
        die("Version must be SemVer X.Y.Z")

    ensure_versions_equal(args.version)

    prefix = {"py": "py-v", "npm": "npm-v", "rs": "rs-v"}[args.target]
    tag = f"{prefix}{args.version}"
    create_tag(tag, args.push)


if __name__ == "__main__":
    main()

