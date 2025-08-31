#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SPEC_FILE = ROOT / "documentation/protocol/spec.md"
PYPROJECT = ROOT / "pyproject.toml"
PKG_JSON = ROOT / "sdks/js_sdk/package.json"
CARGO = ROOT / "sdks/rust_sdk/Cargo.toml"
SETUP_PY = ROOT / "sdks/py_sdk/setup.py"
JS_INDEX = ROOT / "sdks/js_sdk/src/index.ts"

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def die(msg: str):
    print(msg, file=sys.stderr)
    sys.exit(1)


def read_spec_version(text: str) -> str:
    for line in text.splitlines():
        m = re.match(r"^Version:\s*([0-9]+\.[0-9]+\.[0-9]+)", line.strip())
        if m:
            return m.group(1)
    die("Could not find spec version line in spec.md")


def write_spec_version(text: str, version: str) -> str:
    today = dt.date.today().isoformat()
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("Version:"):
            lines[i] = f"Version: {version} ({today})"
            return "\n".join(lines) + ("\n" if text.endswith("\n") else "")
    die("Could not replace spec version line in spec.md")


def read_py_version(text: str) -> str:
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
    die("Could not find version in pyproject.toml [project]")


def write_py_version(text: str, version: str) -> str:
    out = []
    in_project = False
    done = False
    for line in text.splitlines():
        s = line
        if line.strip().startswith("[project]"):
            in_project = True
        elif in_project and line.strip().startswith("["):
            in_project = False
        if in_project and re.match(r"\s*version\s*=\s*\"[^\"]+\"", line):
            s = re.sub(r"(version\s*=\s*\")[^\"]+(\")", rf"\g<1>{version}\2", line)
            done = True
        out.append(s)
    if not done:
        die("Failed to update version in pyproject.toml")
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def read_rs_version(text: str) -> str:
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
    die("Could not find version in Cargo.toml [package]")


def write_rs_version(text: str, version: str) -> str:
    out = []
    in_pkg = False
    done = False
    for line in text.splitlines():
        s = line
        if line.strip().startswith("[package]"):
            in_pkg = True
        elif in_pkg and line.strip().startswith("["):
            in_pkg = False
        if in_pkg and re.match(r"\s*version\s*=\s*\"[^\"]+\"", line):
            s = re.sub(r"(version\s*=\s*\")[^\"]+(\")", rf"\g<1>{version}\2", line)
            done = True
        out.append(s)
    if not done:
        die("Failed to update version in Cargo.toml")
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def main():
    ap = argparse.ArgumentParser(description="Bump spec and SDK versions in lockstep")
    ap.add_argument("version", help="SemVer X.Y.Z")
    ap.add_argument("--stage", action="store_true", help="Create a staged commit with the bump")
    args = ap.parse_args()

    v = args.version
    if not SEMVER_RE.match(v):
        die(f"Version must be SemVer X.Y.Z, got '{v}'")

    spec_text = SPEC_FILE.read_text(encoding="utf-8")
    py_text = PYPROJECT.read_text(encoding="utf-8")
    pkg = json.loads(PKG_JSON.read_text(encoding="utf-8"))
    cargo_text = CARGO.read_text(encoding="utf-8")
    setup_text = SETUP_PY.read_text(encoding="utf-8") if SETUP_PY.exists() else ""
    js_index_text = JS_INDEX.read_text(encoding="utf-8") if JS_INDEX.exists() else ""

    # Update contents
    new_spec = write_spec_version(spec_text, v)
    new_py = write_py_version(py_text, v)
    pkg["version"] = v
    new_pkg_text = json.dumps(pkg, indent=2) + "\n"
    new_cargo = write_rs_version(cargo_text, v)

    # Update SDK-specific version carriers, if present
    if setup_text:
        setup_text = re.sub(r"(version\s*=\s*\")[^\"]+(\")", rf"\g<1>{v}\2", setup_text, count=1)
    if js_index_text:
        js_index_text = re.sub(r"export const version = '\d+\.\d+\.\d+';", f"export const version = '{v}';", js_index_text)

    # Write back
    SPEC_FILE.write_text(new_spec, encoding="utf-8")
    PYPROJECT.write_text(new_py, encoding="utf-8")
    PKG_JSON.write_text(new_pkg_text, encoding="utf-8")
    CARGO.write_text(new_cargo, encoding="utf-8")
    if setup_text:
        SETUP_PY.write_text(setup_text, encoding="utf-8")
    if js_index_text:
        JS_INDEX.write_text(js_index_text, encoding="utf-8")

    # Verify reads
    spec_after = read_spec_version(SPEC_FILE.read_text(encoding="utf-8"))
    py_after = read_py_version(PYPROJECT.read_text(encoding="utf-8"))
    pkg_after = json.loads(PKG_JSON.read_text(encoding="utf-8"))["version"]
    rs_after = read_rs_version(CARGO.read_text(encoding="utf-8"))

    if not (spec_after == py_after == pkg_after == rs_after == v):
        die(f"Post-write verification failed: spec={spec_after} py={py_after} js={pkg_after} rs={rs_after}")

    print(f"Bumped versions to {v}")

    if args.stage:
        import subprocess
        files = [
            str(SPEC_FILE.relative_to(ROOT)),
            str(PYPROJECT.relative_to(ROOT)),
            str(PKG_JSON.relative_to(ROOT)),
            str(CARGO.relative_to(ROOT)),
        ]
        if SETUP_PY.exists():
            files.append(str(SETUP_PY.relative_to(ROOT)))
        if JS_INDEX.exists():
            files.append(str(JS_INDEX.relative_to(ROOT)))
        subprocess.run(["git", "add", *files], check=True)
        # Keep subject short per repo guidelines
        subprocess.run(["git", "commit", "-m", f"Release: bump versions to {v}"], check=True)
        print("Staged and committed version bump.")


if __name__ == "__main__":
    main()
