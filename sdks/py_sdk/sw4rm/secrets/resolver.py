from __future__ import annotations

import os
from typing import Mapping, Tuple

from .backend import SecretsBackend
from .errors import SecretNotFound
from .types import Scope, SecretKey, SecretSource


class Resolver:
    """Resolve secrets with a defined precedence.

    Precedence: explicit > environment variable > scoped secret > global secret.
    Returns a tuple of (value, source).
    """

    def __init__(self, backend: SecretsBackend, env: Mapping[str, str] | None = None) -> None:
        self._backend = backend
        self._env = env or os.environ

    def resolve(
        self,
        key: SecretKey,
        scope: Scope,
        *,
        explicit: str | None = None,
        env_var: str | None = None,
    ) -> Tuple[str, SecretSource]:
        # 1. Explicit (CLI flag or provided argument)
        if explicit is not None:
            return explicit, SecretSource.CLI
        # 2. Environment variable
        if env_var and env_var in self._env and self._env[env_var] != "":
            return self._env[env_var], SecretSource.ENV
        # 3. Scoped secret
        try:
            v = self._backend.get(scope, key)
            return v, SecretSource.SCOPED if not scope.is_global else SecretSource.GLOBAL
        except SecretNotFound:
            pass
        # 4. Global secret fallback
        if not scope.is_global:
            v = self._backend.get(Scope(None), key)
            return v, SecretSource.GLOBAL
        # Not found anywhere
        raise SecretNotFound(scope.label(), key.key)
