from google.protobuf import timestamp_pb2 as _timestamp_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class LogEvent(_message.Message):
    __slots__ = ("ts", "correlation_id", "agent_id", "event_type", "level", "details_json")
    TS_FIELD_NUMBER: _ClassVar[int]
    CORRELATION_ID_FIELD_NUMBER: _ClassVar[int]
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    EVENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    LEVEL_FIELD_NUMBER: _ClassVar[int]
    DETAILS_JSON_FIELD_NUMBER: _ClassVar[int]
    ts: _timestamp_pb2.Timestamp
    correlation_id: str
    agent_id: str
    event_type: str
    level: str
    details_json: str
    def __init__(self, ts: _Optional[_Union[_timestamp_pb2.Timestamp, _Mapping]] = ..., correlation_id: _Optional[str] = ..., agent_id: _Optional[str] = ..., event_type: _Optional[str] = ..., level: _Optional[str] = ..., details_json: _Optional[str] = ...) -> None: ...

class IngestResponse(_message.Message):
    __slots__ = ("ok",)
    OK_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    def __init__(self, ok: bool = ...) -> None: ...
