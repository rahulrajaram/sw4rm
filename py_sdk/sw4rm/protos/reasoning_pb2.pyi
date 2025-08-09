from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class ParallelismCheckRequest(_message.Message):
    __slots__ = ("scope_a", "scope_b")
    SCOPE_A_FIELD_NUMBER: _ClassVar[int]
    SCOPE_B_FIELD_NUMBER: _ClassVar[int]
    scope_a: str
    scope_b: str
    def __init__(self, scope_a: _Optional[str] = ..., scope_b: _Optional[str] = ...) -> None: ...

class ParallelismCheckResponse(_message.Message):
    __slots__ = ("confidence_score", "notes")
    CONFIDENCE_SCORE_FIELD_NUMBER: _ClassVar[int]
    NOTES_FIELD_NUMBER: _ClassVar[int]
    confidence_score: float
    notes: str
    def __init__(self, confidence_score: _Optional[float] = ..., notes: _Optional[str] = ...) -> None: ...

class DebateEvaluateRequest(_message.Message):
    __slots__ = ("negotiation_id", "proposal_a", "proposal_b", "intensity")
    NEGOTIATION_ID_FIELD_NUMBER: _ClassVar[int]
    PROPOSAL_A_FIELD_NUMBER: _ClassVar[int]
    PROPOSAL_B_FIELD_NUMBER: _ClassVar[int]
    INTENSITY_FIELD_NUMBER: _ClassVar[int]
    negotiation_id: str
    proposal_a: str
    proposal_b: str
    intensity: str
    def __init__(self, negotiation_id: _Optional[str] = ..., proposal_a: _Optional[str] = ..., proposal_b: _Optional[str] = ..., intensity: _Optional[str] = ...) -> None: ...

class DebateEvaluateResponse(_message.Message):
    __slots__ = ("confidence_score", "notes")
    CONFIDENCE_SCORE_FIELD_NUMBER: _ClassVar[int]
    NOTES_FIELD_NUMBER: _ClassVar[int]
    confidence_score: float
    notes: str
    def __init__(self, confidence_score: _Optional[float] = ..., notes: _Optional[str] = ...) -> None: ...
