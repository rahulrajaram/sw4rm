from __future__ import annotations

class SecretError(Exception):
    pass


class SecretNotFound(SecretError):
    def __init__(self, scope: str, key: str):
        super().__init__(f"secret not found: scope={scope} key={key}")
        self.scope = scope
        self.key = key


class SecretScopeError(SecretError):
    pass


class SecretBackendError(SecretError):
    pass


class SecretPermissionError(SecretError):
    pass


class SecretValidationError(SecretError):
    pass
