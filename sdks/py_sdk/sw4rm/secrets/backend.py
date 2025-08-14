from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, Protocol, Tuple

from .types import Scope, SecretKey, SecretValue


class SecretsBackend(Protocol):
    def set(self, scope: Scope, key: SecretKey, value: SecretValue) -> None: ...
    def get(self, scope: Scope, key: SecretKey) -> str: ...
    def list(self, scope: Scope | None = None) -> Dict[Tuple[str | None, str], str]: ...


@dataclass
class Secrets:
    backend: SecretsBackend

    def set(self, scope: Scope, key: SecretKey, value: SecretValue) -> None:
        return self.backend.set(scope, key, value)

    def get(self, scope: Scope, key: SecretKey) -> str:
        return self.backend.get(scope, key)

    def list(self, scope: Scope | None = None) -> Dict[tuple[str | None, str], str]:
        return self.backend.list(scope)
