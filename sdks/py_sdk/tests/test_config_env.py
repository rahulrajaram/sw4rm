import os
from sw4rm.config import from_env
from sw4rm import constants as C


def test_from_env_overrides(monkeypatch):
    monkeypatch.setenv("AGENT_ID", "aid")
    monkeypatch.setenv("AGENT_NAME", "aname")
    monkeypatch.setenv(C.ENV_ROUTER_ADDR, "rtr:1234")
    monkeypatch.setenv(C.ENV_REGISTRY_ADDR, "reg:5678")
    cfg = from_env()
    assert cfg.agent_id == "aid" and cfg.name == "aname"
    assert cfg.endpoints.router_addr == "rtr:1234"
    assert cfg.endpoints.registry_addr == "reg:5678"

