from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ToolDescriptor(_message.Message):
    __slots__ = ("tool_name", "input_schema", "output_schema", "idempotent", "needs_worktree", "default_timeout_s", "max_concurrency", "side_effects")
    TOOL_NAME_FIELD_NUMBER: _ClassVar[int]
    INPUT_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    OUTPUT_SCHEMA_FIELD_NUMBER: _ClassVar[int]
    IDEMPOTENT_FIELD_NUMBER: _ClassVar[int]
    NEEDS_WORKTREE_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_TIMEOUT_S_FIELD_NUMBER: _ClassVar[int]
    MAX_CONCURRENCY_FIELD_NUMBER: _ClassVar[int]
    SIDE_EFFECTS_FIELD_NUMBER: _ClassVar[int]
    tool_name: str
    input_schema: str
    output_schema: str
    idempotent: bool
    needs_worktree: bool
    default_timeout_s: int
    max_concurrency: int
    side_effects: str
    def __init__(self, tool_name: _Optional[str] = ..., input_schema: _Optional[str] = ..., output_schema: _Optional[str] = ..., idempotent: bool = ..., needs_worktree: bool = ..., default_timeout_s: _Optional[int] = ..., max_concurrency: _Optional[int] = ..., side_effects: _Optional[str] = ...) -> None: ...

class ProviderRegisterRequest(_message.Message):
    __slots__ = ("provider_id", "tools")
    PROVIDER_ID_FIELD_NUMBER: _ClassVar[int]
    TOOLS_FIELD_NUMBER: _ClassVar[int]
    provider_id: str
    tools: _containers.RepeatedCompositeFieldContainer[ToolDescriptor]
    def __init__(self, provider_id: _Optional[str] = ..., tools: _Optional[_Iterable[_Union[ToolDescriptor, _Mapping]]] = ...) -> None: ...

class ProviderRegisterResponse(_message.Message):
    __slots__ = ("ok", "reason")
    OK_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    reason: str
    def __init__(self, ok: bool = ..., reason: _Optional[str] = ...) -> None: ...

class DescribeToolsRequest(_message.Message):
    __slots__ = ("provider_id",)
    PROVIDER_ID_FIELD_NUMBER: _ClassVar[int]
    provider_id: str
    def __init__(self, provider_id: _Optional[str] = ...) -> None: ...

class DescribeToolsResponse(_message.Message):
    __slots__ = ("tools",)
    TOOLS_FIELD_NUMBER: _ClassVar[int]
    tools: _containers.RepeatedCompositeFieldContainer[ToolDescriptor]
    def __init__(self, tools: _Optional[_Iterable[_Union[ToolDescriptor, _Mapping]]] = ...) -> None: ...
