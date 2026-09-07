#!/usr/bin/env python3
"""Bump every spec/SDK/export/lockfile version without changing dependencies."""
import argparse
import subprocess

from release_contract import ROOT, bump, reference_document, schema_document


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="SemVer X.Y.Z")
    parser.add_argument("--stage", action="store_true", help="Stage and commit the version changes")
    args = parser.parse_args()
    paths = bump(ROOT, args.version)
    reference = "documentation/reference/release-contract.md"
    (ROOT / reference).parent.mkdir(parents=True, exist_ok=True)
    (ROOT / reference).write_text(reference_document(ROOT))
    schema = "documentation/reference/protobuf.md"
    (ROOT / schema).write_text(schema_document(ROOT))
    print(f"Bumped {len(paths)} files to {args.version}; refreshed the release reference")
    if args.stage:
        subprocess.run(["git", "add", *paths, reference, schema], cwd=ROOT, check=True)
        subprocess.run(["git", "commit", "-m", f"chore: bump versions to {args.version}"], cwd=ROOT, check=True)


if __name__ == "__main__":
    main()
