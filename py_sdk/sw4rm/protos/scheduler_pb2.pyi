from google.protobuf import duration_pb2 as _duration_pb2
import common_pb2 as _common_pb2
from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Iterable as _Iterable, Mapping as _Mapping, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class SubmitTaskRequest(_message.Message):
    __slots__ = ("agent_id", "task_id", "priority", "params", "content_type", "scope")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    PRIORITY_FIELD_NUMBER: _ClassVar[int]
    PARAMS_FIELD_NUMBER: _ClassVar[int]
    CONTENT_TYPE_FIELD_NUMBER: _ClassVar[int]
    SCOPE_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    task_id: str
    priority: int
    params: bytes
    content_type: str
    scope: str
    def __init__(self, agent_id: _Optional[str] = ..., task_id: _Optional[str] = ..., priority: _Optional[int] = ..., params: _Optional[bytes] = ..., content_type: _Optional[str] = ..., scope: _Optional[str] = ...) -> None: ...

class SubmitTaskResponse(_message.Message):
    __slots__ = ("accepted", "reason")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    reason: str
    def __init__(self, accepted: bool = ..., reason: _Optional[str] = ...) -> None: ...

class PreemptRequest(_message.Message):
    __slots__ = ("agent_id", "task_id", "reason")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    task_id: str
    reason: str
    def __init__(self, agent_id: _Optional[str] = ..., task_id: _Optional[str] = ..., reason: _Optional[str] = ...) -> None: ...

class PreemptResponse(_message.Message):
    __slots__ = ("enqueued",)
    ENQUEUED_FIELD_NUMBER: _ClassVar[int]
    enqueued: bool
    def __init__(self, enqueued: bool = ...) -> None: ...

class ShutdownAgentRequest(_message.Message):
    __slots__ = ("agent_id", "grace_period")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    GRACE_PERIOD_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    grace_period: _duration_pb2.Duration
    def __init__(self, agent_id: _Optional[str] = ..., grace_period: _Optional[_Union[_duration_pb2.Duration, _Mapping]] = ...) -> None: ...

class ShutdownAgentResponse(_message.Message):
    __slots__ = ("ok",)
    OK_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    def __init__(self, ok: bool = ...) -> None: ...

class PollActivityBufferRequest(_message.Message):
    __slots__ = ("agent_id",)
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    def __init__(self, agent_id: _Optional[str] = ...) -> None: ...

class ActivityEntry(_message.Message):
    __slots__ = ("task_id", "repo_id", "worktree_id", "branch", "description", "timestamp")
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    REPO_ID_FIELD_NUMBER: _ClassVar[int]
    WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    BRANCH_FIELD_NUMBER: _ClassVar[int]
    DESCRIPTION_FIELD_NUMBER: _ClassVar[int]
    TIMESTAMP_FIELD_NUMBER: _ClassVar[int]
    task_id: str
    repo_id: str
    worktree_id: str
    branch: str
    description: str
    timestamp: str
    def __init__(self, task_id: _Optional[str] = ..., repo_id: _Optional[str] = ..., worktree_id: _Optional[str] = ..., branch: _Optional[str] = ..., description: _Optional[str] = ..., timestamp: _Optional[str] = ...) -> None: ...

class PollActivityBufferResponse(_message.Message):
    __slots__ = ("entries",)
    ENTRIES_FIELD_NUMBER: _ClassVar[int]
    entries: _containers.RepeatedCompositeFieldContainer[ActivityEntry]
    def __init__(self, entries: _Optional[_Iterable[_Union[ActivityEntry, _Mapping]]] = ...) -> None: ...

class PurgeActivityRequest(_message.Message):
    __slots__ = ("agent_id", "task_ids")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    TASK_IDS_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    task_ids: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, agent_id: _Optional[str] = ..., task_ids: _Optional[_Iterable[str]] = ...) -> None: ...

class PurgeActivityResponse(_message.Message):
    __slots__ = ("purged",)
    PURGED_FIELD_NUMBER: _ClassVar[int]
    purged: int
    def __init__(self, purged: _Optional[int] = ...) -> None: ...
