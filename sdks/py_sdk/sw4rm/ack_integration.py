from __future__ import annotations

import json
import time
from typing import Any, Dict, Optional, Callable, List
from dataclasses import dataclass

from .clients.router import RouterClient
from .activity_buffer import PersistentActivityBuffer
from .persistence import PersistentActivityRecord
from .acks import build_ack_envelope
from .error_mapping import ErrorCodeMapper, DEFAULT_MAPPER
from . import constants as C


@dataclass
class SendResult:
    """Result of sending a message with ACK tracking."""
    success: bool
    message_id: str
    accepted: bool
    reason: str = ""
    activity_record: Optional[PersistentActivityRecord] = None


class ACKLifecycleManager:
    """Manages ACK lifecycle integration with router responses and activity buffer."""

    def __init__(
        self,
        router_client: RouterClient,
        activity_buffer: PersistentActivityBuffer,
        agent_id: str,
        *,
        auto_ack: bool = True,
        ack_timeout_seconds: Optional[int] = None,
        error_mapper: Optional[ErrorCodeMapper] = None
    ):
        self.router = router_client
        self.buffer = activity_buffer
        self.agent_id = agent_id
        self.auto_ack = auto_ack
        # Spec default ACK timeout is 10s; align with spec for symmetry
        self.ack_timeout_seconds = ack_timeout_seconds or 10
        self.error_mapper = error_mapper or DEFAULT_MAPPER

    def send_message_with_ack(self, envelope: Dict[str, Any]) -> SendResult:
        """Send a message and automatically handle ACK lifecycle."""
        message_id = envelope.get("message_id", "")
        
        try:
            # Record outgoing message
            activity_record = self.buffer.record_outgoing(envelope)
            
            # Send to router
            response = self.router.send_message(envelope)
            
            # Process router response
            accepted = getattr(response, 'accepted', False)
            reason = getattr(response, 'reason', '')
            
            # Generate automatic ACK based on router response
            if self.auto_ack:
                ack_stage = C.FULFILLED if accepted else C.REJECTED
                error_code = C.ERROR_CODE_UNSPECIFIED if accepted else C.VALIDATION_ERROR
                
                # Update activity record
                activity_record.ack(ack_stage, error_code, reason)
                self.buffer.flush()

            return SendResult(
                success=True,
                message_id=message_id,
                accepted=accepted,
                reason=reason,
                activity_record=activity_record
            )

        except Exception as e:
            # Handle send failure using configurable error mapper
            error_code = self.error_mapper.map_exception(e)
            
            if message_id in self.buffer._by_id:
                self.buffer._by_id[message_id].ack(C.FAILED, error_code, str(e))
                self.buffer.flush()

            return SendResult(
                success=False,
                message_id=message_id,
                accepted=False,
                reason=str(e),
                activity_record=self.buffer.get(message_id)
            )

    def process_incoming_ack(self, envelope: Dict[str, Any]) -> Optional[PersistentActivityRecord]:
        """Process an incoming ACK message and update activity records."""
        try:
            # Parse ACK from envelope payload
            if envelope.get("message_type") != C.ACKNOWLEDGEMENT:
                return None

            payload = envelope.get("payload", b"")
            if isinstance(payload, bytes):
                ack_data = json.loads(payload.decode('utf-8'))
            else:
                ack_data = payload

            # Update activity buffer
            updated_record = self.buffer.ack(ack_data)
            if updated_record:
                self.buffer.flush()
            
            return updated_record

        except (json.JSONDecodeError, KeyError) as e:
            print(f"[ACK] Failed to process incoming ACK: {e}")
            return None

    def send_ack(self, ack_for_message_id: str, stage: int, error_code: int = C.ERROR_CODE_UNSPECIFIED, note: str = "") -> SendResult:
        """Send an ACK message for a received message."""
        ack_envelope = build_ack_envelope(
            producer_id=self.agent_id,
            ack_for_message_id=ack_for_message_id,
            ack_stage=stage,
            error_code=error_code,
            note=note
        )
        
        return self.send_message_with_ack(ack_envelope)

    def get_unacked_outgoing(self) -> List[PersistentActivityRecord]:
        """Get outgoing messages that need ACK reconciliation."""
        return [
            record for record in self.buffer.unacked()
            if record.direction == "out"
        ]

    def get_pending_acks(self) -> List[PersistentActivityRecord]:
        """Get incoming messages that still need ACKs to be sent."""
        return [
            record for record in self.buffer.unacked()
            if record.direction == "in" and record.ack_stage in (C.ACK_STAGE_UNSPECIFIED, C.RECEIVED)
        ]

    def reconcile_acks(self) -> List[PersistentActivityRecord]:
        """Find messages that may need retry or follow-up ACKs."""
        now = int(time.time() * 1000)
        timeout_ms = self.ack_timeout_seconds * 1000
        
        stale_records = []
        for record in self.buffer.unacked():
            age_ms = now - record.ts_ms
            if age_ms > timeout_ms:
                stale_records.append(record)
        
        return stale_records

    def auto_ack_received(self, envelope: Dict[str, Any]) -> SendResult:
        """Automatically send RECEIVED ACK for incoming message."""
        message_id = envelope.get("message_id", "")
        
        # Record incoming message first
        self.buffer.record_incoming(envelope)
        
        # Send RECEIVED ACK
        return self.send_ack(message_id, C.RECEIVED)

    def auto_ack_read(self, message_id: str) -> SendResult:
        """Send READ ACK to indicate message has been processed."""
        return self.send_ack(message_id, C.READ)

    def auto_ack_fulfilled(self, message_id: str, note: str = "") -> SendResult:
        """Send FULFILLED ACK to indicate successful processing."""
        return self.send_ack(message_id, C.FULFILLED, note=note)

    def auto_ack_rejected(self, message_id: str, reason: str = "", error_code: int = C.VALIDATION_ERROR) -> SendResult:
        """Send REJECTED ACK to indicate processing rejection."""
        return self.send_ack(message_id, C.REJECTED, error_code=error_code, note=reason)

    def auto_ack_failed(self, message_id: str, error: Exception) -> SendResult:
        """Send FAILED ACK to indicate processing failure."""
        error_code = self.error_mapper.map_exception(error)
        return self.send_ack(message_id, C.FAILED, error_code=error_code, note=str(error))


class MessageProcessor:
    """High-level message processor with automatic ACK handling."""

    def __init__(self, ack_manager: ACKLifecycleManager):
        self.ack_manager = ack_manager
        self._message_handlers: Dict[int, Callable[[Dict[str, Any]], Any]] = {}
        self._default_handler: Optional[Callable[[Dict[str, Any]], Any]] = None

    def register_handler(self, message_type: int, handler: Callable[[Dict[str, Any]], Any]) -> None:
        """Register a handler for a specific message type."""
        self._message_handlers[message_type] = handler

    def set_default_handler(self, handler: Callable[[Dict[str, Any]], Any]) -> None:
        """Set a default handler for unregistered message types."""
        self._default_handler = handler

    def process_message(self, envelope: Dict[str, Any]) -> SendResult:
        """Process an incoming message with automatic ACK handling."""
        message_type = envelope.get("message_type", C.MESSAGE_TYPE_UNSPECIFIED)
        message_id = envelope.get("message_id", "")

        try:
            # Send RECEIVED ACK immediately
            self.ack_manager.auto_ack_received(envelope)

            # Handle ACK messages specially
            if message_type == C.ACKNOWLEDGEMENT:
                self.ack_manager.process_incoming_ack(envelope)
                return SendResult(success=True, message_id=message_id, accepted=True, reason="ACK processed")

            # Send READ ACK before processing
            self.ack_manager.auto_ack_read(message_id)

            # Find and execute handler
            handler = self._message_handlers.get(message_type, self._default_handler)
            
            if handler:
                result = handler(envelope)
                # Send FULFILLED ACK on successful processing
                return self.ack_manager.auto_ack_fulfilled(message_id, f"Processed by {handler.__name__}")
            else:
                # No handler available - reject
                return self.ack_manager.auto_ack_rejected(
                    message_id, 
                    f"No handler for message type {message_type}",
                    C.UNSUPPORTED_MESSAGE_TYPE
                )

        except Exception as e:
            # Send FAILED ACK on processing error
            return self.ack_manager.auto_ack_failed(message_id, e)
