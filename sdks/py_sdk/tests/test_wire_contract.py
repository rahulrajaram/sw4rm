"""Exercise the public wire client against an independent fixture service."""
import importlib.util
from pathlib import Path

import grpc
import pytest
from google.protobuf.descriptor import FieldDescriptor

from sw4rm.clients import ProtocolClient

SERVER = Path(__file__).resolve().parents[3] / "tests/sdk_parity/wire_contract_server.py"
SPEC = importlib.util.spec_from_file_location("sw4rm_wire_oracle", SERVER)
oracle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(oracle)


def from_value(name, value):
    message = oracle.message_type(name)()
    for key, item in value.items():
        field = message.DESCRIPTOR.fields_by_name[key]
        if field.message_type and field.message_type.GetOptions().map_entry:
            value_field = field.message_type.fields_by_name["value"]
            for map_key, entry in item.items():
                if value_field.message_type:
                    getattr(message, key)[map_key].CopyFrom(scalar_value(value_field, entry))
                else:
                    getattr(message, key)[map_key] = scalar_value(value_field, entry)
        elif field.label == FieldDescriptor.LABEL_REPEATED:
            for entry in item:
                if field.message_type:
                    getattr(message, key).add().CopyFrom(scalar_value(field, entry))
                else:
                    getattr(message, key).append(scalar_value(field, entry))
        elif field.message_type:
            getattr(message, key).CopyFrom(scalar_value(field, item))
        else:
            setattr(message, key, scalar_value(field, item))
    return message


def scalar_value(field, value):
    if field.message_type:
        return from_value(field.message_type.full_name, value)
    if field.type == FieldDescriptor.TYPE_BYTES:
        return bytes.fromhex(value)
    if field.type in (FieldDescriptor.TYPE_INT64, FieldDescriptor.TYPE_UINT64):
        return int(value)
    return value


@pytest.mark.parametrize("vector", oracle.CONTRACT["vectors"], ids=lambda vector: vector["id"])
def test_every_canonical_message(vector):
    expected = from_value(vector["type"], vector["value"])
    message_type = oracle.message_type(vector["type"])
    wire = bytes.fromhex(vector["wire_hex"])
    assert message_type.FromString(wire) == expected
    assert message_type.FromString(expected.SerializeToString()) == expected
    # Byte canonicality: deterministic re-encoding must reproduce the
    # recorded wire bytes exactly. Maps have no wire-defined order, so the
    # corpus is written with sorted map keys and compared deterministically
    # (R24).
    assert expected.SerializeToString(deterministic=True) == wire


@pytest.fixture(scope="module")
def client():
    with oracle.serve() as port, grpc.insecure_channel(f"127.0.0.1:{port}") as channel:
        yield ProtocolClient(channel)


@pytest.mark.parametrize("rpc", oracle.CONTRACT["rpcs"], ids=lambda rpc: rpc["path"])
@pytest.mark.parametrize("variant", ["sample", "edge"])
def test_every_canonical_rpc(client, rpc, variant):
    request = oracle.fixture_message(rpc["request"], variant)
    options = {"timeout": 3, "metadata": (("sw4rm-vector", variant),)}
    if rpc["server_streaming"]:
        assert list(client.stream(rpc["path"], request, **options)) == [
            oracle.fixture_message(rpc["response"], v) for v in ("sample", "edge")]
    else:
        assert client.call(rpc["path"], request, **options) == oracle.fixture_message(rpc["response"], variant)


def test_all_rpc_paths_are_exposed():
    assert set(ProtocolClient.rpc_paths()) == {rpc["path"] for rpc in oracle.CONTRACT["rpcs"]}


def test_wire_client_preserves_rpc_error(client):
    request = oracle.fixture_message("sw4rm.router.SendMessageRequest")
    with pytest.raises(grpc.RpcError) as failure:
        client.call("/sw4rm.router.RouterService/SendMessage", request,
                    metadata=(("sw4rm-error", "1"),), timeout=3)
    assert failure.value.code() == grpc.StatusCode.INVALID_ARGUMENT


def test_wire_client_rejects_invalid_dispatch(client):
    request = oracle.fixture_message("sw4rm.router.StreamRequest")
    with pytest.raises(TypeError, match="SendMessageRequest"):
        client.call("/sw4rm.router.RouterService/SendMessage", request)
    with pytest.raises(ValueError, match="requires stream"):
        client.call("/sw4rm.router.RouterService/StreamIncoming", request)
    with pytest.raises(ValueError, match="Unknown canonical"):
        client.call("/sw4rm.router.RouterService/Invented", request)
