from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class BindRequest(_message.Message):
    __slots__ = ("agent_id", "repo_id", "worktree_id")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    REPO_ID_FIELD_NUMBER: _ClassVar[int]
    WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    repo_id: str
    worktree_id: str
    def __init__(self, agent_id: _Optional[str] = ..., repo_id: _Optional[str] = ..., worktree_id: _Optional[str] = ...) -> None: ...

class BindResponse(_message.Message):
    __slots__ = ("ok", "reason")
    OK_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    reason: str
    def __init__(self, ok: bool = ..., reason: _Optional[str] = ...) -> None: ...

class UnbindRequest(_message.Message):
    __slots__ = ("agent_id",)
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    def __init__(self, agent_id: _Optional[str] = ...) -> None: ...

class UnbindResponse(_message.Message):
    __slots__ = ("ok",)
    OK_FIELD_NUMBER: _ClassVar[int]
    ok: bool
    def __init__(self, ok: bool = ...) -> None: ...

class SwitchRequest(_message.Message):
    __slots__ = ("agent_id", "target_worktree_id", "requires_hitl")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    TARGET_WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    REQUIRES_HITL_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    target_worktree_id: str
    requires_hitl: bool
    def __init__(self, agent_id: _Optional[str] = ..., target_worktree_id: _Optional[str] = ..., requires_hitl: bool = ...) -> None: ...

class SwitchApprove(_message.Message):
    __slots__ = ("agent_id", "target_worktree_id", "ttl_ms")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    TARGET_WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    TTL_MS_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    target_worktree_id: str
    ttl_ms: int
    def __init__(self, agent_id: _Optional[str] = ..., target_worktree_id: _Optional[str] = ..., ttl_ms: _Optional[int] = ...) -> None: ...

class SwitchReject(_message.Message):
    __slots__ = ("agent_id", "reason")
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    REASON_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    reason: str
    def __init__(self, agent_id: _Optional[str] = ..., reason: _Optional[str] = ...) -> None: ...

class StatusRequest(_message.Message):
    __slots__ = ("agent_id",)
    AGENT_ID_FIELD_NUMBER: _ClassVar[int]
    agent_id: str
    def __init__(self, agent_id: _Optional[str] = ...) -> None: ...

class StatusResponse(_message.Message):
    __slots__ = ("repo_id", "worktree_id", "state")
    REPO_ID_FIELD_NUMBER: _ClassVar[int]
    WORKTREE_ID_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    repo_id: str
    worktree_id: str
    state: str
    def __init__(self, repo_id: _Optional[str] = ..., worktree_id: _Optional[str] = ..., state: _Optional[str] = ...) -> None: ...
