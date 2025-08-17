from __future__ import annotations

import base64
import json
from typing import Any, Dict


def parse_negotiation_event(raw: bytes | str) -> Dict[str, Any]:
    if isinstance(raw, bytes):
        try:
            raw = raw.decode('utf-8')
        except Exception:
            return {"kind": "unknown"}
    try:
        obj = json.loads(raw)
        if not isinstance(obj, dict) or 'kind' not in obj:
            return {"kind": "unknown"}
        return obj
    except Exception:
        return {"kind": "unknown"}


def decode_b64(s: str | None) -> bytes | None:
    if not s:
        return None
    return base64.b64decode(s)

