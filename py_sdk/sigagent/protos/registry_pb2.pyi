from google.protobuf import timestamp_pb2 as _timestamp_pb2
import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class AgentDescriptor(_message.Message):
    __slots__ = ("agent_id", "name", "description", "capabilities", "communication_class", "modalities_supported", "reasoning_connectors", "public_key")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    CAPABILITIES_FIELD_NUMBER: _ClassVar[int]
    COMMUNICATION_CLASS_FIELD_NUMBER: _ClassVar[int]
    MODALITIES_SUPPORTED_FIELD_NUMBER: _ClassVar[int]
    REASONING_CONNECTORS_FIELD_NUMBER: _ClassVar[int]
    PUBLIC_KEY_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    name: str
    description: str
    capabilities: _containers.RepeatedScalarFieldContainer[str]
    communication_class: _common_pb2.CommunicationClass
    modalities_supported: _containers.RepeatedScalarFieldContainer[str]
    reasoning_connectors: _containers.RepeatedScalarFieldContainer[str]
    public_key: bytes
    def __init__(self, agent_id: _Optional[str] = ..., name: _Optional[str] = ..., description: _Optional[str] = ..., capabilities: _Optional[_Iterable[str]] = ..., communication_class: _Optional[_Union[_common_pb2.CommunicationClass, str]] = ..., modalities_supported: _Optional[_Iterable[str]] = ..., reasoning_connectors: _Optional[_Iterable[str]] = ..., public_key: _Optional[bytes] = ...) -> None: ...

class RegisterAgentRequest(_message.Message):
    __slots__ = ("agent",)
    AGENT_FIELD_NUMBER: _ClassVar[int]
    agent: AgentDescriptor
    def __init__(self, agent: _Optional[_Union[AgentDescriptor, _Mapping]] = ...) -> None: ...

class RegisterAgentResponse(_message.Message):
    __slots__ = ("accepted", "reason")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    reason: str
    def __init__(self, accepted: bool = ..., reason: _Optional[str] = ...) -> None: ...

class HeartbeatRequest(_message.Message):
    __slots__ = ("agent_id", "state", "health")
    class HealthEntry(_message.Message):
        __slots__ = ("key", "value")
        KEY_FIELD_NUMBER: _ClassVar[int]
        VALUE_FIELD_NUMBER: _ClassVar[int]
        key: str
        value: str
        def __init__(self, key: _Optional[str] = ..., value: _Optional[str] = ...) -> None: ...
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    HEALTH_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    state: _common_pb2.AgentState
    health: _containers.ScalarMap[str, str]
    def __init__(self, agent_id: _Optional[str] = ..., state: _Optional[_Union[_common_pb2.AgentState, str]] = ..., health: _Optional[_Mapping[str, str]] = ...) -> None: ...

class HeartbeatResponse(_message.Message):
    __slots__ = ("ok",)
    OK_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    def __init__(self, ok: bool = ...) -> None: ...

class DeregisterAgentRequest(_message.Message):
    __slots__ = ("agent_id", "reason")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    reason: str
    def __init__(self, agent_id: _Optional[str] = ..., reason: _Optional[str] = ...) -> None: ...

class DeregisterAgentResponse(_message.Message):
    __slots__ = ("ok",)
    OK_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    def __init__(self, ok: bool = ...) -> None: ...
