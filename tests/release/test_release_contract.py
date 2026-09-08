"""Release gates must detect real package/version/schema drift."""
from pathlib import Path
import shutil
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from release_contract import (CARRIERS, bump, inventory,
                              protocol_copy_errors, reference_document, resolve_base_ref,
                              rpc_inventory, schema_document, staged_base_version_errors,
                              version_errors)  # noqa: E402


@pytest.fixture
def release_tree(tmp_path):
    paths = frozenset(c.path for c in CARRIERS)
    for path in paths:
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path, target)
    shutil.copytree(ROOT / 'protos', tmp_path / 'protos')
    shutil.copytree(ROOT / 'sdks/rust_sdk/protos', tmp_path / 'sdks/rust_sdk/protos')
    return tmp_path


@pytest.mark.parametrize('index', range(len(CARRIERS)))
def test_every_carrier_is_guarded(release_tree, index):
    carrier = CARRIERS[index]
    path = release_tree / carrier.path
    path.write_text(carrier.update(path.read_text(), '9.9.9'))
    assert version_errors(inventory(lambda p: (release_tree / p).read_text()))


def test_bump_covers_all_sdks_exports_and_locks_without_changing_dependencies(release_tree):
    import json
    import tomllib
    package = release_tree / 'sdks/js_sdk/package-lock.json'
    rust = release_tree / 'sdks/rust_sdk/Cargo.lock'
    before_js = json.loads(package.read_text())['packages']
    before_rs = tomllib.loads(rust.read_text())['package']
    bump(release_tree, '0.8.0')
    assert all(v == '0.8.0' for _, v in inventory(lambda p: (release_tree / p).read_text()))
    assert {k: v for k, v in json.loads(package.read_text())['packages'].items() if k} == {k: v for k, v in before_js.items() if k}
    assert [p for p in tomllib.loads(rust.read_text())['package'] if p['name'] != 'sw4rm-sdk'] == [p for p in before_rs if p['name'] != 'sw4rm-sdk']


def test_missing_carrier_fails_before_writing(release_tree):
    path = release_tree / CARRIERS[-1].path
    path.write_text('no version here')
    before = (release_tree / CARRIERS[0].path).read_bytes()
    with pytest.raises(ValueError, match='missing version'):
        bump(release_tree, '0.8.0')
    assert (release_tree / CARRIERS[0].path).read_bytes() == before


def test_proto_drift_requires_docs_and_packaged_copy_update(release_tree):
    reference, schema = reference_document(release_tree), schema_document(release_tree)
    path = release_tree / 'protos/router.proto'
    path.write_text(path.read_text().replace('rpc AckDelivery', 'rpc ConfirmDelivery'))
    assert protocol_copy_errors(release_tree)
    assert reference_document(release_tree) != reference
    assert schema_document(release_tree) != schema


def test_wire_field_change_updates_full_schema_even_when_rpcs_unchanged(release_tree):
    before = schema_document(release_tree)
    path = release_tree / 'protos/router.proto'
    path.write_text(path.read_text().replace('int64 seq = 2', 'int64 seq = 99'))
    assert schema_document(release_tree) != before
    assert protocol_copy_errors(release_tree)


def test_rpc_inventory_matches_real_protobuf_compiler(tmp_path):
    import grpc_tools
    from grpc_tools import protoc
    from google.protobuf.descriptor_pb2 import FileDescriptorSet
    output = tmp_path / 'schema.pb'
    assert protoc.main(['protoc', f'-I{ROOT / "protos"}', f'-I{Path(grpc_tools.__file__).parent / "_proto"}',
                        f'--descriptor_set_out={output}', *map(str, sorted((ROOT / 'protos').glob('*.proto')))]) == 0
    descriptors = FileDescriptorSet.FromString(output.read_bytes())
    expected = {(f'{f.package}.{s.name}', m.name) for f in descriptors.file for s in f.service for m in s.method}
    assert {(r.service, r.method) for r in rpc_inventory(ROOT)} == expected


def _git(cwd, *args):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def test_staged_release_check_requires_one_bump_per_branch(tmp_path):
    _git(tmp_path, 'init', '-b', 'master')
    _git(tmp_path, 'config', 'user.email', 'tests@example.invalid')
    _git(tmp_path, 'config', 'user.name', 'Release tests')
    path = tmp_path / 'documentation/protocol/spec.md'
    path.parent.mkdir(parents=True)
    path.write_text('Version: 0.7.0\n')
    (tmp_path / 'protos').mkdir()
    (tmp_path / 'protos/router.proto').write_text('syntax = "proto3";\n')
    _git(tmp_path, 'add', '.')
    _git(tmp_path, 'commit', '-m', 'base')
    _git(tmp_path, 'branch', 'release-base')
    path.write_text('Version: 0.7.0\n')
    (tmp_path / 'protos/router.proto').write_text('syntax = "proto3";\nmessage Changed {}\n')
    _git(tmp_path, 'add', '.')
    assert staged_base_version_errors(tmp_path, 'HEAD') == (
        'Protocol/SDK changed: version 0.7.0 must exceed base 0.7.0',)
    path.write_text('Version: 0.8.0\n')
    _git(tmp_path, 'add', str(path.relative_to(tmp_path)))
    assert staged_base_version_errors(tmp_path, 'HEAD') == ()
    _git(tmp_path, 'commit', '-m', 'first release bump')
    (tmp_path / 'protos/router.proto').write_text('syntax = "proto3";\nmessage ChangedAgain {}\n')
    _git(tmp_path, 'add', 'protos/router.proto')
    assert staged_base_version_errors(tmp_path, 'release-base') == ()
    assert staged_base_version_errors(tmp_path, 'HEAD') == (
        'Protocol/SDK changed: version 0.8.0 must exceed base 0.8.0',)


def test_staged_check_reads_index_when_unstaged_worktree_is_fixed(tmp_path):
    _git(tmp_path, 'init', '-b', 'master')
    _git(tmp_path, 'config', 'user.email', 'tests@example.invalid')
    _git(tmp_path, 'config', 'user.name', 'Release tests')
    path = tmp_path / 'documentation/protocol/spec.md'
    path.parent.mkdir(parents=True)
    path.write_text('Version: 0.7.0\n')
    (tmp_path / 'protos').mkdir()
    proto = tmp_path / 'protos/router.proto'
    proto.write_text('syntax = "proto3";\n')
    _git(tmp_path, 'add', '.')
    _git(tmp_path, 'commit', '-m', 'base')
    proto.write_text('syntax = "proto3";\nmessage Changed {}\n')
    _git(tmp_path, 'add', '.')
    path.write_text('Version: 0.8.0\n')
    assert staged_base_version_errors(tmp_path, 'HEAD') == (
        'Protocol/SDK changed: version 0.7.0 must exceed base 0.7.0',)


def test_base_resolution_uses_known_origin_branch_and_rejects_missing(tmp_path):
    _git(tmp_path, 'init', '-b', 'master')
    _git(tmp_path, 'config', 'user.email', 'tests@example.invalid')
    _git(tmp_path, 'config', 'user.name', 'Release tests')
    (tmp_path / 'file').write_text('base')
    _git(tmp_path, 'add', 'file')
    _git(tmp_path, 'commit', '-m', 'base')
    _git(tmp_path, 'branch', 'feature')
    _git(tmp_path, 'update-ref', 'refs/remotes/origin/master', 'HEAD')
    assert resolve_base_ref(tmp_path) == 'origin/master'
    _git(tmp_path, 'update-ref', '-d', 'refs/remotes/origin/master')
    with pytest.raises(ValueError, match='Unable to resolve release base'):
        resolve_base_ref(tmp_path)


def test_staged_cli_ignores_worktree_and_catches_index_mismatch(release_tree, monkeypatch):
    import release_contract
    _git(release_tree, 'init', '-b', 'master')
    _git(release_tree, 'config', 'user.email', 'tests@example.invalid')
    _git(release_tree, 'config', 'user.name', 'Release tests')
    _git(release_tree, 'add', '.')
    _git(release_tree, 'commit', '-m', 'base')
    monkeypatch.setattr(release_contract, 'ROOT', release_tree)
    monkeypatch.setattr(sys, 'argv', ['release_contract', '--staged', '--base-ref', 'HEAD'])
    carrier = CARRIERS[1]
    path = release_tree / carrier.path
    original = path.read_text()
    path.write_text('invalid unstaged content')
    assert release_contract.main() == 0
    path.write_text(carrier.update(original, '9.9.9'))
    _git(release_tree, 'add', carrier.path)
    path.write_text(original)
    assert release_contract.main() == 1


def test_origin_head_resolves_two_default_branch_names(tmp_path):
    _git(tmp_path, 'init', '-b', 'master')
    _git(tmp_path, 'config', 'user.email', 'tests@example.invalid')
    _git(tmp_path, 'config', 'user.name', 'Release tests')
    _git(tmp_path, 'commit', '--allow-empty', '-m', 'base')
    for name in ('master', 'main'):
        _git(tmp_path, 'update-ref', f'refs/remotes/origin/{name}', 'HEAD')
    with pytest.raises(ValueError, match='Both origin/master and origin/main'):
        resolve_base_ref(tmp_path)
    _git(tmp_path, 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
    assert resolve_base_ref(tmp_path) == 'origin/main'
