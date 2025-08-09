import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class HitlInvocation(_message.Message):
    __slots__ = ("reason_type", "context", "proposed_actions", "priority")
    REASON_TYPE_FIELD_NUMBER: _ClassVar[int]
    CONTEXT_FIELD_NUMBER: _ClassVar[int]
    PROPOSED_ACTIONS_FIELD_NUMBER: _ClassVar[int]
    PRIORITY_FIELD_NUMBER: _ClassVar[int]
    reason_type: _common_pb2.HitlReasonType
    context: bytes
    proposed_actions: _containers.RepeatedScalarFieldContainer[str]
    priority: int
    def __init__(self, reason_type: _Optional[_Union[_common_pb2.HitlReasonType, str]] = ..., context: _Optional[bytes] = ..., proposed_actions: _Optional[_Iterable[str]] = ..., priority: _Optional[int] = ...) -> None: ...

class HitlDecision(_message.Message):
    __slots__ = ("action", "decision_payload", "rationale")
    ACTION_FIELD_NUMBER: _ClassVar[int]
    DECISION_PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    RATIONALE_FIELD_NUMBER: _ClassVar[int]
    action: str
    decision_payload: bytes
    rationale: str
    def __init__(self, action: _Optional[str] = ..., decision_payload: _Optional[bytes] = ..., rationale: _Optional[str] = ...) -> None: ...
