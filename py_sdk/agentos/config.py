from dataclasses import dataclass, field
from typing import Dict


@dataclass
class Endpoints:
    registry: str = "localhost:50051"
    router: str = "localhost:50052"
    scheduler: str = "localhost:50053"
    hitl: str = "localhost:50054"
    worktree: str = "localhost:50055"
    negotiation: str = "localhost:50056"
    reasoning: str = "localhost:50057"
    logging: str = "localhost:50058"
    tool: str = "localhost:50059"


@dataclass
class AgentConfig:
    agent_id: str
    name: str
    description: str = ""
    capabilities: list[str] = field(default_factory=list)
    communication_class: str = "STANDARD"
    modalities_supported: list[str] = field(default_factory=lambda: ["application/json"])
    reasoning_connectors: list[str] = field(default_factory=list)
    public_key: bytes | None = None
    endpoints: Endpoints = field(default_factory=Endpoints)
    heartbeat_interval_s: int = 10
    max_inbound_buffer: int = 10
    ack_timeout_s: int = 10
    metadata: Dict[str, str] = field(default_factory=dict)

