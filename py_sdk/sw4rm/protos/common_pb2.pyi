from google.protobuf import timestamp_pb2 as _timestamp_pb2
from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class MessageType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    MESSAGE_TYPE_UNSPECIFIED: _ClassVar[MessageType]
    CONTROL: _ClassVar[MessageType]
    DATA: _ClassVar[MessageType]
    HEARTBEAT: _ClassVar[MessageType]
    NOTIFICATION: _ClassVar[MessageType]
    ACKNOWLEDGEMENT: _ClassVar[MessageType]
    HITL_INVOCATION: _ClassVar[MessageType]
    WORKTREE_CONTROL: _ClassVar[MessageType]
    NEGOTIATION: _ClassVar[MessageType]
    TOOL_CALL: _ClassVar[MessageType]
    TOOL_RESULT: _ClassVar[MessageType]
    TOOL_ERROR: _ClassVar[MessageType]

class AckStage(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ACK_STAGE_UNSPECIFIED: _ClassVar[AckStage]
    RECEIVED: _ClassVar[AckStage]
    READ: _ClassVar[AckStage]
    FULFILLED: _ClassVar[AckStage]
    REJECTED: _ClassVar[AckStage]
    FAILED: _ClassVar[AckStage]
    TIMED_OUT: _ClassVar[AckStage]

class ErrorCode(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    ERROR_CODE_UNSPECIFIED: _ClassVar[ErrorCode]
    BUFFER_FULL: _ClassVar[ErrorCode]
    NO_ROUTE: _ClassVar[ErrorCode]
    ACK_TIMEOUT: _ClassVar[ErrorCode]
    AGENT_UNAVAILABLE: _ClassVar[ErrorCode]
    AGENT_SHUTDOWN: _ClassVar[ErrorCode]
    VALIDATION_ERROR: _ClassVar[ErrorCode]
    PERMISSION_DENIED: _ClassVar[ErrorCode]
    UNSUPPORTED_MESSAGE_TYPE: _ClassVar[ErrorCode]
    OVERSIZE_PAYLOAD: _ClassVar[ErrorCode]
    TOOL_TIMEOUT: _ClassVar[ErrorCode]
    PARTIAL_DELIVERY: _ClassVar[ErrorCode]
    FORCED_PREEMPTION: _ClassVar[ErrorCode]
    TTL_EXPIRED: _ClassVar[ErrorCode]
    INTERNAL_ERROR: _ClassVar[ErrorCode]

class AgentState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    AGENT_STATE_UNSPECIFIED: _ClassVar[AgentState]
    INITIALIZING: _ClassVar[AgentState]
    RUNNABLE: _ClassVar[AgentState]
    SCHEDULED: _ClassVar[AgentState]
    RUNNING: _ClassVar[AgentState]
    WAITING: _ClassVar[AgentState]
    WAITING_RESOURCES: _ClassVar[AgentState]
    SUSPENDED: _ClassVar[AgentState]
    RESUMED: _ClassVar[AgentState]
    COMPLETED: _ClassVar[AgentState]
    FAILED_STATE: _ClassVar[AgentState]
    SHUTTING_DOWN: _ClassVar[AgentState]
    RECOVERING: _ClassVar[AgentState]

class CommunicationClass(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    COMM_CLASS_UNSPECIFIED: _ClassVar[CommunicationClass]
    PRIVILEGED: _ClassVar[CommunicationClass]
    STANDARD: _ClassVar[CommunicationClass]
    BULK: _ClassVar[CommunicationClass]

class DebateIntensity(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DEBATE_INTENSITY_UNSPECIFIED: _ClassVar[DebateIntensity]
    LOWEST: _ClassVar[DebateIntensity]
    LOW: _ClassVar[DebateIntensity]
    MEDIUM: _ClassVar[DebateIntensity]
    HIGH: _ClassVar[DebateIntensity]
    HIGHEST: _ClassVar[DebateIntensity]

class HitlReasonType(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    HITL_REASON_UNSPECIFIED: _ClassVar[HitlReasonType]
    CONFLICT: _ClassVar[HitlReasonType]
    SECURITY_APPROVAL: _ClassVar[HitlReasonType]
    TASK_ESCALATION: _ClassVar[HitlReasonType]
    MANUAL_OVERRIDE: _ClassVar[HitlReasonType]
    WORKTREE_OVERRIDE: _ClassVar[HitlReasonType]
    DEBATE_DEADLOCK: _ClassVar[HitlReasonType]
    TOOL_PRIVILEGE_ESCALATION: _ClassVar[HitlReasonType]
    CONNECTOR_APPROVAL: _ClassVar[HitlReasonType]
MESSAGE_TYPE_UNSPECIFIED: MessageType
CONTROL: MessageType
DATA: MessageType
HEARTBEAT: MessageType
NOTIFICATION: MessageType
ACKNOWLEDGEMENT: MessageType
HITL_INVOCATION: MessageType
WORKTREE_CONTROL: MessageType
NEGOTIATION: MessageType
TOOL_CALL: MessageType
TOOL_RESULT: MessageType
TOOL_ERROR: MessageType
ACK_STAGE_UNSPECIFIED: AckStage
RECEIVED: AckStage
READ: AckStage
FULFILLED: AckStage
REJECTED: AckStage
FAILED: AckStage
TIMED_OUT: AckStage
ERROR_CODE_UNSPECIFIED: ErrorCode
BUFFER_FULL: ErrorCode
NO_ROUTE: ErrorCode
ACK_TIMEOUT: ErrorCode
AGENT_UNAVAILABLE: ErrorCode
AGENT_SHUTDOWN: ErrorCode
VALIDATION_ERROR: ErrorCode
PERMISSION_DENIED: ErrorCode
UNSUPPORTED_MESSAGE_TYPE: ErrorCode
OVERSIZE_PAYLOAD: ErrorCode
TOOL_TIMEOUT: ErrorCode
PARTIAL_DELIVERY: ErrorCode
FORCED_PREEMPTION: ErrorCode
TTL_EXPIRED: ErrorCode
INTERNAL_ERROR: ErrorCode
AGENT_STATE_UNSPECIFIED: AgentState
INITIALIZING: AgentState
RUNNABLE: AgentState
SCHEDULED: AgentState
RUNNING: AgentState
WAITING: AgentState
WAITING_RESOURCES: AgentState
SUSPENDED: AgentState
RESUMED: AgentState
COMPLETED: AgentState
FAILED_STATE: AgentState
SHUTTING_DOWN: AgentState
RECOVERING: AgentState
COMM_CLASS_UNSPECIFIED: CommunicationClass
PRIVILEGED: CommunicationClass
STANDARD: CommunicationClass
BULK: CommunicationClass
DEBATE_INTENSITY_UNSPECIFIED: DebateIntensity
LOWEST: DebateIntensity
LOW: DebateIntensity
MEDIUM: DebateIntensity
HIGH: DebateIntensity
HIGHEST: DebateIntensity
HITL_REASON_UNSPECIFIED: HitlReasonType
CONFLICT: HitlReasonType
SECURITY_APPROVAL: HitlReasonType
TASK_ESCALATION: HitlReasonType
MANUAL_OVERRIDE: HitlReasonType
WORKTREE_OVERRIDE: HitlReasonType
DEBATE_DEADLOCK: HitlReasonType
TOOL_PRIVILEGE_ESCALATION: HitlReasonType
CONNECTOR_APPROVAL: HitlReasonType

class Envelope(_message.Message):
    __slots__ = ("message_id", "idempotency_token", "producer_id", "correlation_id", "sequence_number", "retry_count", "message_type", "content_type", "content_length", "repo_id", "worktree_id", "hlc_timestamp", "ttl_ms", "timestamp", "payload")
    MESSAGE_ID_FIELD_NUMBER: _ClassVar[int]
    IDEMPOTENCY_TOKEN_FIELD_NUMBER: _ClassVar[int]
    PRODUCER_ID_FIELD_NUMBER: _ClassVar[int]
    CORRELATION_ID_FIELD_NUMBER: _ClassVar[int]
    SEQUENCE_NUMBER_FIELD_NUMBER: _ClassVar[int]
    RETRY_COUNT_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_TYPE_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    CONTENT_LENGTH_FIELD_NUMBER: _ClassVar[int]
    REPO_ID_FIELD_NUMBER: _ClassVar[int]
    WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    HLC_TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    TTL_MS_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    message_id: str
    idempotency_token: str
    producer_id: str
    correlation_id: str
    sequence_number: int
    retry_count: int
    message_type: MessageType
    content_type: str
    content_length: int
    repo_id: str
    worktree_id: str
    hlc_timestamp: str
    ttl_ms: int
    timestamp: _timestamp_pb2.Timestamp
    payload: bytes
    def __init__(self, message_id: _Optional[str] = ..., idempotency_token: _Optional[str] = ..., producer_id: _Optional[str] = ..., correlation_id: _Optional[str] = ..., sequence_number: _Optional[int] = ..., retry_count: _Optional[int] = ..., message_type: _Optional[_Union[MessageType, str]] = ..., content_type: _Optional[str] = ..., content_length: _Optional[int] = ..., repo_id: _Optional[str] = ..., worktree_id: _Optional[str] = ..., hlc_timestamp: _Optional[str] = ..., ttl_ms: _Optional[int] = ..., timestamp: _Optional[_Union[_timestamp_pb2.Timestamp, _Mapping]] = ..., payload: _Optional[bytes] = ...) -> None: ...

class Ack(_message.Message):
    __slots__ = ("ack_for_message_id", "ack_stage", "error_code", "note")
    ACK_FOR_MESSAGE_ID_FIELD_NUMBER: _ClassVar[int]
    ACK_STAGE_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    NOTE_FIELD_NUMBER: _ClassVar[int]
    ack_for_message_id: str
    ack_stage: AckStage
    error_code: ErrorCode
    note: str
    def __init__(self, ack_for_message_id: _Optional[str] = ..., ack_stage: _Optional[_Union[AckStage, str]] = ..., error_code: _Optional[_Union[ErrorCode, str]] = ..., note: _Optional[str] = ...) -> None: ...

class Empty(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...
