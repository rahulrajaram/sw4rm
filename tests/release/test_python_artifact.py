"""Exercise wheel isolation with namespace packages and absent runtime files."""
from pathlib import Path
import subprocess
import sys
import zipfile

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from check_python_artifact import _probe_unpacked_wheel, check  # noqa: E402


def test_wheel_probe_imports_implicit_namespace_from_installed_layout(tmp_path):
    wheel = tmp_path / 'namespace.whl'
    with zipfile.ZipFile(wheel, 'w') as archive:
        archive.writestr('sw4rm/__init__.py', '')
        archive.writestr('sw4rm/protos/router_pb2.py', 'MARKER = "wheel"\n')
    _probe_unpacked_wheel(wheel, '''
import pathlib, sys
installed = pathlib.Path(sys.argv[1])
sys.path.insert(0, str(installed))
from sw4rm.protos import router_pb2
assert router_pb2.MARKER == "wheel"
assert pathlib.Path(router_pb2.__file__).is_relative_to(installed)
''', ())


def test_wheel_probe_does_not_use_pythonpath_to_supply_missing_module(tmp_path, monkeypatch):
    fallback = tmp_path / 'checkout'
    fallback.mkdir()
    (fallback / 'missing_wheel_module.py').write_text('MARKER = "checkout"\n')
    monkeypatch.setenv('PYTHONPATH', str(fallback))
    wheel = tmp_path / 'empty.whl'
    with zipfile.ZipFile(wheel, 'w'):
        pass
    with pytest.raises(subprocess.CalledProcessError):
        _probe_unpacked_wheel(wheel, 'import missing_wheel_module', ())


def test_wheel_check_rejects_missing_runtime_files(tmp_path):
    wheel = tmp_path / 'empty.whl'
    with zipfile.ZipFile(wheel, 'w'):
        pass
    with pytest.raises(ValueError, match='Wheel missing runtime files'):
        check(wheel)
