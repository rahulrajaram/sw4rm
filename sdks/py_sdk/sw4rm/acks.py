from __future__ import annotations

import json
from typing import Optional, Dict, Any

from .envelope import build_envelope
from . import constants as C


def build_ack(
    *,
    ack_for_message_id: str,
    ack_stage: int,
    error_code: int = C.ERROR_CODE_UNSPECIFIED,
    note: str = "",
) -> Dict[str, Any]:
    """Return a plain dict representing an Ack message payload.

    This structure matches fields in sw4rm.common.Ack and is intended to be
    serialized (e.g., JSON) and placed into an Envelope payload for transport.
    """
    return {
        "ack_for_message_id": ack_for_message_id,
        "ack_stage": ack_stage,
        "error_code": error_code,
        "note": note,
    }


def build_ack_envelope(
    *,
    producer_id: str,
    ack_for_message_id: str,
    ack_stage: int,
    error_code: int = C.ERROR_CODE_UNSPECIFIED,
    note: str = "",
    correlation_id: Optional[str] = None,
    sequence_number: Optional[int] = None,
) -> Dict[str, Any]:
    """Build an Envelope carrying an Ack payload.

    - content_type is set to application/json and payload is a JSON encoding of the Ack.
    - message_type is set to ACKNOWLEDGEMENT.
    """
    payload = json.dumps(
        build_ack(
            ack_for_message_id=ack_for_message_id,
            ack_stage=ack_stage,
            error_code=error_code,
            note=note,
        )
    ).encode("utf-8")
    return build_envelope(
        producer_id=producer_id,
        message_type=C.ACKNOWLEDGEMENT,
        content_type="application/json",
        payload=payload,
        correlation_id=correlation_id,
        sequence_number=sequence_number,
    )


def map_exception_to_error_code(exc: Exception) -> int:
    """Map exception to error code using the default mapper.
    
    This function is deprecated. Use error_mapping.DEFAULT_MAPPER directly
    or create a custom DictErrorCodeMapper for more control.
    """
    from .error_mapping import DEFAULT_MAPPER
    return DEFAULT_MAPPER.map_exception(exc)


def ack_for_send_result(
    *,
    producer_id: str,
    original_msg_id: str,
    accepted: bool,
    reason: str = "",
) -> Dict[str, Any]:
    """Helper to build an ACK envelope from a Router.SendMessageResponse-like result."""
    if accepted:
        stage = C.FULFILLED
        code = C.ERROR_CODE_UNSPECIFIED
    else:
        stage = C.REJECTED
        code = C.VALIDATION_ERROR if reason else C.ERROR_CODE_UNSPECIFIED
    return build_ack_envelope(
        producer_id=producer_id,
        ack_for_message_id=original_msg_id,
        ack_stage=stage,
        error_code=code,
        note=reason,
    )

