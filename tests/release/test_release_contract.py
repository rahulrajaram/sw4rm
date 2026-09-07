"""Release gates must detect real package/version/schema drift."""
from pathlib import Path
import shutil
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from release_contract import CARRIERS, bump, inventory, protocol_copy_errors, reference_document, rpc_inventory, schema_document, version_errors  # noqa: E402


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
