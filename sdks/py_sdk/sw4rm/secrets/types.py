from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class SecretSource(str, Enum):
    CLI = "cli"
    ENV = "env"
    SCOPED = "scoped"
    GLOBAL = "global"


@dataclass(frozen=True)
class Scope:
    name: Optional[str] = None  # None represents global scope

    @property
    def is_global(self) -> bool:
        return self.name is None

    def label(self) -> str:
        return self.name if self.name else "global"


@dataclass(frozen=True)
class SecretKey:
    key: str

    def __post_init__(self) -> None:
        # Simple schema: provider.<name>.<field> or custom dotted keys
        if not self.key or any(p.strip() == "" for p in self.key.split(".")):
            raise ValueError("secret key must be a dotted identifier without empty segments")


@dataclass(frozen=True)
class SecretValue:
    value: str

    MAX_LEN = 8 * 1024  # 8KB default limit

    def __post_init__(self) -> None:
        if len(self.value) > self.MAX_LEN:
            raise ValueError("secret value exceeds maximum allowed length (8KB)")
