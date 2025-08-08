import common_pb2 as _common_pb2
from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class NegotiationOpen(_message.Message):
    __slots__ = ("negotiation_id", "correlation_id", "topic", "participants", "intensity", "debate_timeout")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    CORRELATION_ID_FIELD_NUMBER: _ClassVar[int]
    TOPIC_FIELD_NUMBER: _ClassVar[int]
    PARTICIPANTS_FIELD_NUMBER: _ClassVar[int]
    INTENSITY_FIELD_NUMBER: _ClassVar[int]
    DEBATE_TIMEOUT_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    correlation_id: str
    topic: str
    participants: _containers.RepeatedScalarFieldContainer[str]
    intensity: _common_pb2.DebateIntensity
    debate_timeout: _duration_pb2.Duration
    def __init__(self, negotiation_id: _Optional[str] = ..., correlation_id: _Optional[str] = ..., topic: _Optional[str] = ..., participants: _Optional[_Iterable[str]] = ..., intensity: _Optional[_Union[_common_pb2.DebateIntensity, str]] = ..., debate_timeout: _Optional[_Union[_duration_pb2.Duration, _Mapping]] = ...) -> None: ...

class Proposal(_message.Message):
    __slots__ = ("negotiation_id", "from_agent", "content_type", "payload")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    FROM_AGENT_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    from_agent: str
    content_type: str
    payload: bytes
    def __init__(self, negotiation_id: _Optional[str] = ..., from_agent: _Optional[str] = ..., content_type: _Optional[str] = ..., payload: _Optional[bytes] = ...) -> None: ...

class CounterProposal(_message.Message):
    __slots__ = ("negotiation_id", "from_agent", "content_type", "payload")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    FROM_AGENT_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    PAYLOAD_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    from_agent: str
    content_type: str
    payload: bytes
    def __init__(self, negotiation_id: _Optional[str] = ..., from_agent: _Optional[str] = ..., content_type: _Optional[str] = ..., payload: _Optional[bytes] = ...) -> None: ...

class Evaluation(_message.Message):
    __slots__ = ("negotiation_id", "from_agent", "confidence_score", "notes")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    FROM_AGENT_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_SCORE_FIELD_NUMBER: _ClassVar[int]
    NOTES_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    from_agent: str
    confidence_score: float
    notes: str
    def __init__(self, negotiation_id: _Optional[str] = ..., from_agent: _Optional[str] = ..., confidence_score: _Optional[float] = ..., notes: _Optional[str] = ...) -> None: ...

class Decision(_message.Message):
    __slots__ = ("negotiation_id", "decided_by", "content_type", "result")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    DECIDED_BY_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    decided_by: str
    content_type: str
    result: bytes
    def __init__(self, negotiation_id: _Optional[str] = ..., decided_by: _Optional[str] = ..., content_type: _Optional[str] = ..., result: _Optional[bytes] = ...) -> None: ...

class AbortRequest(_message.Message):
    __slots__ = ("negotiation_id", "reason")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    reason: str
    def __init__(self, negotiation_id: _Optional[str] = ..., reason: _Optional[str] = ...) -> None: ...
