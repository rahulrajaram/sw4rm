#!/usr/bin/env python3
"""Import a built wheel in isolation, using only already-installed dependencies."""
from __future__ import annotations
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile


def _probe_unpacked_wheel(wheel: Path, code: str, modules: tuple[str, ...]) -> None:
    # Wheels are installed as files, not imported as ZIP archives. In particular,
    # ZIP imports cannot discover this wheel's implicit protobuf namespace.
    with tempfile.TemporaryDirectory(prefix='sw4rm-wheel-') as temporary:
        with zipfile.ZipFile(wheel) as archive:
            archive.extractall(temporary)
        subprocess.run([sys.executable, '-I', '-c', code, temporary, *modules],
                       cwd=temporary, check=True)


def check(wheel: Path) -> None:
    with zipfile.ZipFile(wheel) as archive:
        names = frozenset(archive.namelist())
        required = frozenset({
            'sw4rm/clients/router.py', 'sw4rm/protos/router_pb2.py',
            'sw4rm/protos/router_pb2_grpc.py', 'sw4rm_policies/quorum.py',
            'sw4rm/clients/protocol.py', 'sw4rm/clients/protocol_methods.py',
        })
        missing = required - names
        if missing:
            raise ValueError(f'Wheel missing runtime files: {sorted(missing)}')
    code = '''
import importlib, pathlib, sys
installed = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(installed))
import sw4rm
assert pathlib.Path(sw4rm.__file__).resolve().is_relative_to(installed), sw4rm.__file__
from sw4rm.protos import router_pb2
from sw4rm.clients.router import RouterClient
from sw4rm.clients import ProtocolClient
from sw4rm.clients.protocol_methods import PROTOCOL_METHODS
from sw4rm.envelope import compute_idempotency_token
from sw4rm_policies.aggregation import aggregate_votes
assert 'seq' in router_pb2.StreamItem.DESCRIPTOR.fields_by_name
assert 'AckDelivery' in router_pb2.DESCRIPTOR.services_by_name['RouterService'].methods_by_name
assert callable(RouterClient.ack_delivery)
for name in sys.argv[2:]:
    importlib.import_module(name)
class BindingChannel:
    def __init__(self): self.paths = set()
    def unary_unary(self, path, **kwargs):
        self.paths.add(path)
        return lambda request, **options: None
    unary_stream = unary_unary
channel = BindingChannel()
for module in sorted({entry[0] for entry in PROTOCOL_METHODS.values()}):
    stub_module = importlib.import_module('sw4rm.protos.' + module + '_pb2_grpc')
    for name in dir(stub_module):
        if name.endswith('Stub'): getattr(stub_module, name)(channel)
assert set(ProtocolClient.rpc_paths()) == channel.paths
assert callable(compute_idempotency_token)
for name, module in tuple(sys.modules.items()):
    if name.split('.')[0] not in ('sw4rm', 'sw4rm_policies'):
        continue
    filename = getattr(module, '__file__', None)
    locations = [filename] if filename else list(getattr(module, '__path__', ()))
    assert locations and all(pathlib.Path(location).resolve().is_relative_to(installed)
                             for location in locations), (name, locations)
print('Wheel imports, ACK and all canonical RPC bindings OK:', sw4rm.__version__)
'''
    modules = tuple(name[:-3].replace('/', '.') for name in sorted(names)
                    if name.startswith('sw4rm/protos/') and name.endswith(('_pb2.py', '_pb2_grpc.py')))
    _probe_unpacked_wheel(wheel, code, modules)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('wheel', type=Path)
    args = parser.parse_args()
    check(args.wheel)


if __name__ == '__main__':
    main()
