from google.protobuf import duration_pb2 as _duration_pb2
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class ExecutionPolicy(_message.Message):
    __slots__ = ("timeout", "max_retries", "backoff", "worktree_required", "network_policy", "privilege_level", "budget_cpu_ms", "budget_wall_ms")
    TIMEOUT_FIELD_NUMBER: _ClassVar[int]
    MAX_RETRIES_FIELD_NUMBER: _ClassVar[int]
    BACKOFF_FIELD_NUMBER: _ClassVar[int]
    WORKTREE_REQUIRED_FIELD_NUMBER: _ClassVar[int]
    NETWORK_POLICY_FIELD_NUMBER: _ClassVar[int]
    PRIVILEGE_LEVEL_FIELD_NUMBER: _ClassVar[int]
    BUDGET_CPU_MS_FIELD_NUMBER: _ClassVar[int]
    BUDGET_WALL_MS_FIELD_NUMBER: _ClassVar[int]
    timeout: _duration_pb2.Duration
    max_retries: int
    backoff: str
    worktree_required: bool
    network_policy: str
    privilege_level: str
    budget_cpu_ms: int
    budget_wall_ms: int
    def __init__(self, timeout: _Optional[_Union[_duration_pb2.Duration, _Mapping]] = ..., max_retries: _Optional[int] = ..., backoff: _Optional[str] = ..., worktree_required: bool = ..., network_policy: _Optional[str] = ..., privilege_level: _Optional[str] = ..., budget_cpu_ms: _Optional[int] = ..., budget_wall_ms: _Optional[int] = ...) -> None: ...

class ToolCall(_message.Message):
    __slots__ = ("call_id", "tool_name", "provider_id", "content_type", "args", "policy", "stream")
    CALL_ID_FIELD_NUMBER: _ClassVar[int]
    TOOL_NAME_FIELD_NUMBER: _ClassVar[int]
    PROVIDER_ID_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    ARGS_FIELD_NUMBER: _ClassVar[int]
    POLICY_FIELD_NUMBER: _ClassVar[int]
    STREAM_FIELD_NUMBER: _ClassVar[int]
    call_id: str
    tool_name: str
    provider_id: str
    content_type: str
    args: bytes
    policy: ExecutionPolicy
    stream: bool
    def __init__(self, call_id: _Optional[str] = ..., tool_name: _Optional[str] = ..., provider_id: _Optional[str] = ..., content_type: _Optional[str] = ..., args: _Optional[bytes] = ..., policy: _Optional[_Union[ExecutionPolicy, _Mapping]] = ..., stream: bool = ...) -> None: ...

class ToolFrame(_message.Message):
    __slots__ = ("call_id", "frame_no", "final", "content_type", "data", "summary")
    CALL_ID_FIELD_NUMBER: _ClassVar[int]
    FRAME_NO_FIELD_NUMBER: _ClassVar[int]
    FINAL_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    DATA_FIELD_NUMBER: _ClassVar[int]
    SUMMARY_FIELD_NUMBER: _ClassVar[int]
    call_id: str
    frame_no: int
    final: bool
    content_type: str
    data: bytes
    summary: bytes
    def __init__(self, call_id: _Optional[str] = ..., frame_no: _Optional[int] = ..., final: bool = ..., content_type: _Optional[str] = ..., data: _Optional[bytes] = ..., summary: _Optional[bytes] = ...) -> None: ...

class ToolError(_message.Message):
    __slots__ = ("call_id", "error_code", "message")
    CALL_ID_FIELD_NUMBER: _ClassVar[int]
    ERROR_CODE_FIELD_NUMBER: _ClassVar[int]
    MESSAGE_FIELD_NUMBER: _ClassVar[int]
    call_id: str
    error_code: str
    message: str
    def __init__(self, call_id: _Optional[str] = ..., error_code: _Optional[str] = ..., message: _Optional[str] = ...) -> None: ...
