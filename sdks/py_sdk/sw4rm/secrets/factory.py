from __future__ import annotations

import logging
import os
from typing import Tuple

from .backend import SecretsBackend
from .errors import SecretBackendError
from .backends.file_backend import FileBackend

logger = logging.getLogger(__name__)


def _auto_backend() -> Tuple[SecretsBackend, str]:
    """Return a backend following platform/CI preferences.

    Prefers OS keyring when available; falls back to file backend.
    Returns (backend, backend_name).
    """
    # Use file backend in CI by default
    if os.environ.get("CI"):
        b = FileBackend()
        logger.debug("Using file backend in CI environment")
        return b, "file"
    # Try keyring
    try:
        from .backends.keyring_backend import KeyringBackend

        b = KeyringBackend()
        logger.debug("Using keyring backend")
        return b, "keyring"
    except Exception as e:  # SecretBackendError or ImportError
        logger.debug("Keyring backend unavailable (%s); falling back to file backend", e)
        b = FileBackend()
        return b, "file"


def select_backend(mode: str | None = None) -> Tuple[SecretsBackend, str]:
    """Select backend based on mode/env.

    Mode options: "auto" (default), "file", "keyring".
    Env var: `SW4RM_SECRETS_BACKEND` can override mode when mode is None.
    """
    mode_eff = (mode or os.environ.get("SW4RM_SECRETS_BACKEND") or "auto").lower()
    if mode_eff == "auto":
        return _auto_backend()
    if mode_eff == "file":
        return FileBackend(), "file"
    if mode_eff == "keyring":
        try:
            from .backends.keyring_backend import KeyringBackend

            return KeyringBackend(), "keyring"
        except Exception as e:
            raise SecretBackendError(
                "keyring backend not available; install 'keyring' or choose --backend file"
            ) from e
    raise SecretBackendError(f"unknown backend mode: {mode_eff}")
