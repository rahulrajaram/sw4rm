from __future__ import annotations

import getpass
import os
from typing import Dict, Tuple

from ..errors import SecretBackendError, SecretNotFound
from ..types import Scope, SecretKey, SecretValue


class KeyringBackend:
    """OS keyring-backed secrets store.

    Requires the optional 'keyring' package to be installed.
    Stores credentials with a service name per scope and key.
    """

    def __init__(self, service_prefix: str = "sw4rm") -> None:
        try:
            import keyring  # type: ignore
        except Exception as e:  # pragma: no cover - optional dep
            raise SecretBackendError(
                "keyring backend unavailable; install 'keyring' package or use file backend"
            ) from e
        self._keyring = keyring  # type: ignore
        self._service_prefix = service_prefix
        self._user = getpass.getuser()

    def _service_name(self, scope: Scope) -> str:
        scope_part = scope.name or "global"
        return f"{self._service_prefix}:{scope_part}"

    def set(self, scope: Scope, key: SecretKey, value: SecretValue) -> None:
        service = self._service_name(scope)
        self._keyring.set_password(service, key.key, value.value)

    def get(self, scope: Scope, key: SecretKey) -> str:
        service = self._service_name(scope)
        v = self._keyring.get_password(service, key.key)
        if v is None:
            raise SecretNotFound(scope.label(), key.key)
        return v

    def list(self, scope: Scope | None = None) -> Dict[Tuple[str | None, str], str]:
        # keyring API doesn't support listing; return empty to avoid leaking
        # Implementers can track an index separately if needed.
        return {}
