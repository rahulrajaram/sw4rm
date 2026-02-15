import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
TESTBED_ROOT = REPO_ROOT / "tests" / "inter_swarm_testbed"
MANIFEST_PATH = TESTBED_ROOT / "bootstrap_manifest.json"
COMPOSE_PATH = TESTBED_ROOT / "docker-compose.multi-swarm.yml"


def _load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def test_manifest_has_expected_transport_shape() -> None:
    manifest = _load_manifest()
    assert manifest["schema_version"] == "1.0"
    assert manifest["transport"]["primary_protocol"] == "grpc"
    assert manifest["transport"]["health_rpc"] == "grpc.health.v1.Health/Check"
    assert set(manifest["transport"]["security_profiles"]) == {
        "local-insecure",
        "production-mtls",
    }


def test_manifest_hosts_are_unique_and_port_disjoint() -> None:
    manifest = _load_manifest()
    hosts = manifest["hosts"]
    assert len(hosts) >= 2

    swarm_ids = [host["swarm_id"] for host in hosts]
    assert len(set(swarm_ids)) == len(swarm_ids)

    observed_ports: set[int] = set()
    for host in hosts:
        services = host["services"]
        assert set(services.keys()) == {"registry", "router", "scheduler"}
        for port in services.values():
            assert isinstance(port, int)
            assert port > 0
            assert port not in observed_ports
            observed_ports.add(port)


def test_manifest_bootstrap_commands_expose_required_placeholders() -> None:
    manifest = _load_manifest()
    commands = manifest["bootstrap_commands"]
    for key in ("python_local", "js_local", "rust_local"):
        command = commands[key]
        assert "{registry}" in command
        assert "{router}" in command
        assert "{scheduler}" in command

    assert commands["compose"] == (
        "docker compose -f tests/inter_swarm_testbed/docker-compose.multi-swarm.yml up --build -d"
    )


def test_compose_scaffold_covers_all_manifest_hosts_and_ports() -> None:
    manifest = _load_manifest()
    compose_text = COMPOSE_PATH.read_text(encoding="utf-8")

    for host in manifest["hosts"]:
        swarm_key = host["swarm_id"].replace("-", "_")
        for service_name, port in host["services"].items():
            assert f"{swarm_key}_{service_name}:" in compose_text
            assert f"\"{port}:{port}\"" in compose_text

    assert "inter_swarm_testbed" in compose_text
    assert "grpc.insecure_channel" in compose_text
