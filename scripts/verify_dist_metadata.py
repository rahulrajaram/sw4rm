#!/usr/bin/env python3
from __future__ import annotations

import glob
import io
import os
import sys
import tarfile
import zipfile
from typing import Tuple


def read_wheel_metadata(path: str) -> Tuple[str, str, str]:
    z = zipfile.ZipFile(path)
    meta_paths = [n for n in z.namelist() if n.endswith('.dist-info/METADATA')]
    if not meta_paths:
        raise RuntimeError(f"no METADATA in wheel: {path}")
    data = z.read(meta_paths[0]).decode()
    name = _parse_field(data, 'Name')
    version = _parse_field(data, 'Version')
    mv = _parse_field(data, 'Metadata-Version')
    return name, version, mv


def read_sdist_metadata(path: str) -> Tuple[str, str, str | None]:
    with tarfile.open(path, 'r:gz') as tar:
        member = next((m for m in tar.getmembers() if m.name.endswith('PKG-INFO')), None)
        if not member:
            raise RuntimeError(f"no PKG-INFO in sdist: {path}")
        f = tar.extractfile(member)
        assert f is not None
        data = f.read().decode()
        name = _parse_field(data, 'Name')
        version = _parse_field(data, 'Version')
        mv = _parse_field(data, 'Metadata-Version', required=False)
        return name, version, mv


def _parse_field(text: str, field: str, required: bool = True) -> str:
    prefix = field + ":"
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip()
    if required:
        raise RuntimeError(f"missing field {field}")
    return ""


def main() -> int:
    dist_dir = os.path.join(os.getcwd(), 'dist')
    if not os.path.isdir(dist_dir):
        print('[verify] No dist/ directory found. Run \"make release\" first.')
        return 1

    wheels = sorted(glob.glob(os.path.join(dist_dir, '*.whl')))
    sdists = sorted(glob.glob(os.path.join(dist_dir, '*.tar.gz')))
    if not wheels and not sdists:
        print('[verify] No distributions found in dist/. Build first.')
        return 1

    ok = True
    for w in wheels:
        try:
            name, ver, mv = read_wheel_metadata(w)
            print(f"[ok] wheel: {os.path.basename(w)} -> Name={name} Version={ver} Metadata-Version={mv}")
            # Accept modern metadata versions including 2.4
            if mv not in {'2.1', '2.2', '2.3', '2.4'}:
                print(f"[warn] unexpected Metadata-Version in wheel: {mv}")
        except Exception as e:
            print(f"[error] wheel {os.path.basename(w)}: {e}")
            ok = False

    for s in sdists:
        try:
            name, ver, mv = read_sdist_metadata(s)
            mv_disp = mv or 'n/a'
            print(f"[ok] sdist: {os.path.basename(s)} -> Name={name} Version={ver} Metadata-Version={mv_disp}")
        except Exception as e:
            print(f"[error] sdist {os.path.basename(s)}: {e}")
            ok = False

    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())

