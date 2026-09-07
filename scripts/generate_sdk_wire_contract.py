#!/usr/bin/env python3
"""Derive cross-SDK wire fixtures and Lisp bindings from the canonical protos.

Uses the already installed grpc_tools compiler; never installs dependencies.
Without --write, fail if a checked-in output differs from the canonical schema.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import grpc_tools
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory
from google.protobuf.descriptor import Descriptor, FieldDescriptor
from sdk_wire_rust import render as rust_tests

ROOT = Path(__file__).resolve().parents[1]

# Named fixture variants, each produced for every non-map message.  The RPC
# round-trip tests consume only "sample" and "edge"; all five SDK suites
# consume every variant generically (test-coverage finding 10 / R25).
VARIANTS = ("sample", "edge", "empty", "presence", "single")

# U+1F600 (4-byte UTF-8) exercises the utf8 wire path beyond the 1-2 byte
# range that ASCII + Greek cover.  Decided deliberately NaN-free: NaN has no
# portable equality and each runtime may normalize its bit pattern (R25).
FOUR_BYTE_UTF8 = "\U0001f600"


@dataclass(frozen=True)
class Field:
    name: str
    number: int
    kind: str
    repeated: bool
    target: str | None
    map_entry: bool
    enum_values: tuple[str, ...]


@dataclass(frozen=True)
class Message:
    name: str
    fields: tuple[Field, ...]


@dataclass(frozen=True)
class Rpc:
    path: str
    request: str
    response: str
    server_streaming: bool
    module: str


def descriptors(root: Path) -> tuple[descriptor_pool.DescriptorPool, tuple[str, ...]]:
    sources = tuple(sorted((root / "protos").glob("*.proto")))
    with tempfile.TemporaryDirectory(prefix="sw4rm-schema-") as temporary:
        output = Path(temporary) / "schema.pb"
        subprocess.run(
            [sys.executable, "-m", "grpc_tools.protoc", f"-I{root / 'protos'}",
             f"-I{Path(grpc_tools.__file__).parent / '_proto'}", "--include_imports",
             f"--descriptor_set_out={output}", *(str(p) for p in sources)],
            check=True,
        )
        files = descriptor_pb2.FileDescriptorSet.FromString(output.read_bytes()).file
    pool = descriptor_pool.DescriptorPool()
    for file in files:
        pool.Add(file)
    return pool, tuple(file.name for file in files)


def nested_messages(message: Descriptor) -> tuple[Descriptor, ...]:
    return (message,) + tuple(child for nested in message.nested_types
                              for child in nested_messages(nested))


def message_contract(message: Descriptor) -> Message:
    if message.oneofs:
        raise ValueError(f"Oneof support must be added before generating {message.full_name}")
    return Message(message.full_name, tuple(
        Field(field.name, field.number,
              descriptor_pb2.FieldDescriptorProto.Type.Name(field.type)[5:].lower(),
              field.label == FieldDescriptor.LABEL_REPEATED,
              field.message_type.full_name if field.message_type else None,
              bool(field.message_type and field.message_type.GetOptions().map_entry),
              tuple(field.enum_type.values_by_name) if field.enum_type else ())
        for field in message.fields))


def rpc_contract(pool: descriptor_pool.DescriptorPool, names: tuple[str, ...]) -> tuple[Rpc, ...]:
    methods = tuple((service, method) for name in names
                    for service in pool.FindFileByName(name).services_by_name.values()
                    for method in service.methods)
    if any(method.client_streaming for _, method in methods):
        raise ValueError("Client streaming requires explicit SDK support before generation")
    return tuple(Rpc(f"/{service.full_name}/{method.name}", method.input_type.full_name,
                     method.output_type.full_name, method.server_streaming, Path(service.file.name).stem)
                 for service, method in methods)


def scalar_sample(field: FieldDescriptor, variant: str, index: int = 0):
    if variant == "presence":
        return {FieldDescriptor.TYPE_STRING: "", FieldDescriptor.TYPE_BYTES: b"",
                FieldDescriptor.TYPE_BOOL: False, FieldDescriptor.TYPE_FLOAT: 0.0,
                FieldDescriptor.TYPE_DOUBLE: 0.0}.get(field.type, 0)
    if field.type == FieldDescriptor.TYPE_ENUM:
        # R25: exercise both ends of the value range instead of only the last.
        # Index 0 is the proto3 default everywhere here (serializes as absent),
        # so the sample variant writes the first non-default value (index 1)
        # and edge writes the last declared value.
        values = tuple(field.enum_type.values_by_name.values())
        selected = (1 if len(values) > 1 else 0) if variant == "sample" else -1
        return values[selected].number
    values = {
        FieldDescriptor.TYPE_STRING: (f"{field.name}-{index}-{FOUR_BYTE_UTF8}"
                                      if variant == "sample" else f"{field.name}-{index}-\u03bb"),
        FieldDescriptor.TYPE_BYTES: bytes([0, 255, 128, index]),
        FieldDescriptor.TYPE_BOOL: True,
        # 0.1 is not exactly representable in binary (exercises the rounding
        # path); edge carries -0.0 with the sign bit preserved.  NaN is
        # deliberately absent (no portable equality, per-variant bit
        # normalization across runtimes).
        FieldDescriptor.TYPE_DOUBLE: 0.1 + index if variant == "sample" else -0.0 - index,
        FieldDescriptor.TYPE_FLOAT: 0.1 + index if variant == "sample" else -0.0 - index,
        FieldDescriptor.TYPE_UINT64: (2**64 - 1 if variant == "edge" else 2**53 + 17) - index,
        FieldDescriptor.TYPE_INT64: ((2**53 + 17) - index if variant == "sample"
                                     else -(2**63) + index),
        FieldDescriptor.TYPE_INT32: (7 - index if variant == "sample" else -(2**31) + index),
        FieldDescriptor.TYPE_UINT32: (2**32 - 1 if variant == "edge" else 17) - index,
    }
    if field.type not in values:
        raise ValueError(f"Unhandled sample type: {field.full_name} ({field.type})")
    return values[field.type]


def sample_message(descriptor: Descriptor, variant: str, depth: int = 0):
    if depth > 12:
        raise ValueError(f"Recursive schema requires bounded fixtures: {descriptor.full_name}")
    message = message_factory.GetMessageClass(descriptor)()
    if variant == "empty":
        return message
    # R25: "single" exercises one-element repeated/map fields; every other
    # populated variant keeps two elements ("empty" covers the zero case).
    elements = 1 if variant == "single" else 2
    for field in descriptor.fields:
        if field.message_type and field.message_type.GetOptions().map_entry:
            value_field = field.message_type.fields_by_name["value"]
            for index in range(elements):
                key = "" if variant == "presence" else f"key-{index}"
                if value_field.message_type:
                    getattr(message, field.name)[key].CopyFrom(
                        sample_message(value_field.message_type, "empty" if variant == "presence" else variant, depth + 1))
                else:
                    getattr(message, field.name)[key] = scalar_sample(value_field, variant, index)
        elif field.label == FieldDescriptor.LABEL_REPEATED:
            for index in range(elements):
                if field.message_type:
                    getattr(message, field.name).add().CopyFrom(
                        sample_message(field.message_type, "empty" if variant == "presence" else variant, depth + 1))
                else:
                    getattr(message, field.name).append(scalar_sample(field, variant, index))
        elif field.message_type:
            getattr(message, field.name).CopyFrom(sample_message(
                field.message_type, "empty" if variant == "presence" else variant, depth + 1))
        else:
            setattr(message, field.name, scalar_sample(field, variant))
    return message


def plain_scalar(field: FieldDescriptor, value):
    if field.message_type:
        return plain_message(value)
    if field.type == FieldDescriptor.TYPE_BYTES:
        return value.hex()
    if field.type in (FieldDescriptor.TYPE_INT64, FieldDescriptor.TYPE_UINT64):
        return str(value)
    return value


def plain_message(message) -> dict:
    """Use proto field names, hex bytes, decimal 64-bit integers, numeric enums."""
    def value(field):
        item = getattr(message, field.name)
        if field.message_type and field.message_type.GetOptions().map_entry:
            value_field = field.message_type.fields_by_name["value"]
            return {key: plain_scalar(value_field, item[key]) for key in sorted(item)}
        if field.label == FieldDescriptor.LABEL_REPEATED:
            return [plain_scalar(field, entry) for entry in item]
        return plain_scalar(field, item)
    return {field.name: value(field) for field, _ in message.ListFields()}


def lisp_string(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def lisp_bindings(messages: tuple[Message, ...], rpcs: tuple[Rpc, ...]) -> str:
    def field_row(field: Field) -> str:
        target = lisp_string(field.target) if field.target else "nil"
        return (f"(:{field.name.replace('_', '-')} {field.number} :{field.kind} "
                f"{'t' if field.repeated else 'nil'} {target} {'t' if field.map_entry else 'nil'})")
    schemas = "\n".join(f"    ({lisp_string(message.name)} "
                         f"({' '.join(field_row(f) for f in message.fields)}))" for message in messages)
    methods = "\n".join(f"    ({lisp_string(rpc.path)} {lisp_string(rpc.request)} "
                         f"{lisp_string(rpc.response)} {'t' if rpc.server_streaming else 'nil'})"
                         for rpc in rpcs)
    return (";;;; Generated by scripts/generate_sdk_wire_contract.py --write.\n"
            ";;;; Do not edit; canonical field numbers and RPC types come from protos/.\n"
            "(in-package :sw4rm-sdk)\n\n"
            f"(defparameter *protocol-message-schemas*\n  '(\n{schemas}))\n\n"
            f"(defparameter *protocol-rpc-schemas*\n  '(\n{methods}))\n")


def outputs(root: Path) -> tuple[tuple[str, str], ...]:
    pool, names = descriptors(root)
    descriptors_all = tuple(sorted((nested for name in names
        for message in pool.FindFileByName(name).message_types_by_name.values()
        for nested in nested_messages(message)), key=lambda message: message.full_name))
    messages = tuple(message_contract(message) for message in descriptors_all)
    rpcs = rpc_contract(pool, names)
    fixtures = tuple({"id": f"{desc.full_name}:{variant}", "type": desc.full_name,
                      "value": plain_message(message),
                      "wire_hex": message.SerializeToString(deterministic=True).hex()}
                     for desc in descriptors_all if not desc.GetOptions().map_entry
                     for variant in VARIANTS
                     for message in (sample_message(desc, variant),))
    contract = {
        "schema_version": 1,
        "protos_sha256": hashlib.sha256(b"".join(
            p.name.encode() + b"\0" + p.read_bytes() for p in sorted((root / "protos").glob("*.proto")))).hexdigest(),
        "services": sorted({rpc.path.split('/')[1] for rpc in rpcs}),
        "rpcs": [{"path": rpc.path, "request": rpc.request, "response": rpc.response,
                  "server_streaming": rpc.server_streaming} for rpc in rpcs],
        "messages": {message.name: [{"name": f.name, "number": f.number, "kind": f.kind,
                                      "repeated": f.repeated, "target": f.target,
                                      "map_entry": f.map_entry, "enum_values": f.enum_values} for f in message.fields]
                     for message in messages},
        "vectors": fixtures,
    }
    js_methods = {rpc.path: {"request": rpc.request, "response": rpc.response,
                            "serverStreaming": rpc.server_streaming} for rpc in rpcs}
    python_methods = {rpc.path: (rpc.module, rpc.request, rpc.server_streaming) for rpc in rpcs}
    return (
        ("tests/sdk_parity/wire_probe.proto",
         '// Generated codec test service; not part of the SW4RM protocol.\nsyntax = "proto3";\n'
         'package sw4rm.parity;\n' + ''.join(f'import "{name}";\n' for name in names) +
         'service WireProbe {\n' + ''.join(
             f'  rpc Message{index} (.{message.full_name}) returns (.{message.full_name});\n'
             for index, message in enumerate(descriptors_all) if not message.GetOptions().map_entry) + '}\n'),
        ("sdks/rust_sdk/tests/wire_contract.rs", rust_tests(descriptors_all, rpcs, len(VARIANTS))),
        ("tests/conformance_vectors/wire_vectors.json.gz", json.dumps(contract, indent=2, ensure_ascii=False) + "\n"),
        ("sdks/cl_sdk/src/transport/protocol-bindings.lisp", lisp_bindings(messages, rpcs)),
        ("sdks/js_sdk/src/clients/protocolMethods.ts",
         "// Generated by scripts/generate_sdk_wire_contract.py --write.\n"
         "export const protocolMethods = " + json.dumps(js_methods, indent=2) + " as const;\n"
         "export const protocolMessageFields = " + json.dumps(contract["messages"], indent=2) + " as const;\n"),
        ("sdks/py_sdk/sw4rm/clients/protocol_methods.py",
         '# Generated by scripts/generate_sdk_wire_contract.py --write.\n'
         'from types import MappingProxyType\n\n'
         'PROTOCOL_METHODS = MappingProxyType({\n' +
         ''.join(f'    {path!r}: {value!r},\n' for path, value in python_methods.items()) + '})\n'),
    )


CORPUS_PATH = "tests/conformance_vectors/wire_vectors.json.gz"


def read_generated(path: str) -> str:
    raw = (ROOT / path).read_bytes()
    if path.endswith(".gz"):
        return gzip.decompress(raw).decode()
    return raw.decode()


def write_generated(path: str, content: str) -> None:
    if path.endswith(".gz"):
        # mtime=0 keeps the gzip bytes deterministic for the stale check.
        (ROOT / path).write_bytes(gzip.compress(content.encode(), mtime=0))
    else:
        (ROOT / path).write_text(content)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    generated = outputs(ROOT)
    stale = tuple(path for path, content in generated
                  if not (ROOT / path).exists() or read_generated(path) != content)
    if args.write:
        for path, content in generated:
            write_generated(path, content)
    elif stale:
        print("Stale SDK wire contract: " + ", ".join(stale))
        return 1
    contract = json.loads(read_generated(CORPUS_PATH))
    print(f"Wire contract: {len(contract['services'])} services, {len(contract['rpcs'])} RPCs, "
          f"{len(contract['messages'])} message types, {len(contract['vectors'])} vectors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
