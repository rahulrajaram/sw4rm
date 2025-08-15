from __future__ import annotations

import json
import os
import stat
import tempfile
from pathlib import Path
from typing import Dict, Tuple

from ..errors import SecretBackendError, SecretNotFound, SecretPermissionError
from ..types import Scope, SecretKey, SecretValue


class FileBackend:
    """Permissions-restricted file backend.

    Stores secrets in a single JSON file under the user's config dir.
    Layout:
      { "global": {"key": "value"}, "<hive>": {"key": "value"}, ... }
    """

    def __init__(self, path: Path | None = None) -> None:
        self._path = path or self._default_path()
        self._path.parent.mkdir(parents=True, exist_ok=True)
        # Ensure directory has safe perms on POSIX; best-effort
        try:
            if os.name == "posix":
                os.chmod(self._path.parent, 0o700)
        except Exception:
            pass
        if not self._path.exists():
            self._safe_write({})
            self._enforce_file_perms()
        else:
            self._enforce_file_perms()

    def _default_path(self) -> Path:
        if os.name == "nt":
            base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
            return Path(base) / "sw4rm" / "secrets.json"
        # POSIX
        xdg = os.environ.get("XDG_CONFIG_HOME")
        base = Path(xdg) if xdg else Path.home() / ".config"
        return base / "sw4rm" / "secrets.json"

    def _enforce_file_perms(self) -> None:
        if os.name == "posix":
            try:
                st = self._path.stat()
                # If file has group/other perms, tighten them
                if (st.st_mode & (stat.S_IRWXG | stat.S_IRWXO)) != 0:
                    os.chmod(self._path, 0o600)
            except PermissionError as e:  # pragma: no cover - system dependent
                raise SecretPermissionError("insufficient permissions to adjust secrets file") from e

    def _load(self) -> Dict[str, Dict[str, str]]:
        try:
            with self._path.open("r", encoding="utf-8") as f:
                return json.load(f)
        except FileNotFoundError:
            return {}
        except json.JSONDecodeError as e:
            raise SecretBackendError("secrets file is corrupted; fix or delete it") from e

    def _safe_write(self, data: Dict[str, Dict[str, str]]) -> None:
        tmp_fd, tmp_path = tempfile.mkstemp(dir=str(self._path.parent), prefix=".secrets.")
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, self._path)
            # Ensure perms after replace
            self._enforce_file_perms()
        finally:
            try:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)
            except Exception:
                pass

    def set(self, scope: Scope, key: SecretKey, value: SecretValue) -> None:
        data = self._load()
        bucket = data.setdefault(scope.label(), {})
        bucket[key.key] = value.value
        self._safe_write(data)

    def get(self, scope: Scope, key: SecretKey) -> str:
        data = self._load()
        bucket = data.get(scope.label(), {})
        if key.key not in bucket:
            raise SecretNotFound(scope.label(), key.key)
        return bucket[key.key]

    def list(self, scope: Scope | None = None) -> Dict[Tuple[str | None, str], str]:
        data = self._load()
        out: Dict[Tuple[str | None, str], str] = {}
        if scope is not None:
            bucket = data.get(scope.label(), {})
            for k, v in bucket.items():
                out[(scope.name, k)] = v
            return out
        for scope_name, bucket in data.items():
            for k, v in bucket.items():
                out[(None if scope_name == "global" else scope_name, k)] = v
        return out
