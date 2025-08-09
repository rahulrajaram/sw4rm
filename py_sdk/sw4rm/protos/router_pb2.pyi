import common_pb2 as _common_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SendMessageRequest(_message.Message):
    __slots__ = ("msg",)
    MSG_FIELD_NUMBER: _ClassVar[int]
    msg: _common_pb2.Envelope
    def __init__(self, msg: _Optional[_Union[_common_pb2.Envelope, _Mapping]] = ...) -> None: ...

class SendMessageResponse(_message.Message):
    __slots__ = ("accepted", "reason")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    reason: str
    def __init__(self, accepted: bool = ..., reason: _Optional[str] = ...) -> None: ...

class StreamRequest(_message.Message):
    __slots__ = ("agent_id",)
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    def __init__(self, agent_id: _Optional[str] = ...) -> None: ...

class StreamItem(_message.Message):
    __slots__ = ("msg",)
    MSG_FIELD_NUMBER: _ClassVar[int]
    msg: _common_pb2.Envelope
    def __init__(self, msg: _Optional[_Union[_common_pb2.Envelope, _Mapping]] = ...) -> None: ...
