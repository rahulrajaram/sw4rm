"""Protocol constants mirroring common.proto enums.

These are numeric values to keep the SDK usable without generated stubs
at import time. When pb2 modules are available, prefer using those enums
directly. Values must match common.proto definitions.
"""

# MessageType
MESSAGE_TYPE_UNSPECIFIED = 0
CONTROL = 1
DATA = 2
HEARTBEAT = 3
NOTIFICATION = 4
ACKNOWLEDGEMENT = 5
HITL_INVOCATION = 6
WORKTREE_CONTROL = 7
NEGOTIATION = 8
TOOL_CALL = 9
TOOL_RESULT = 10
TOOL_ERROR = 11

# AckStage
ACK_STAGE_UNSPECIFIED = 0
RECEIVED = 1
READ = 2
FULFILLED = 3
REJECTED = 4
FAILED = 5
TIMED_OUT = 6

# ErrorCode
ERROR_CODE_UNSPECIFIED = 0
BUFFER_FULL = 1
NO_ROUTE = 2
ACK_TIMEOUT = 3
AGENT_UNAVAILABLE = 4
AGENT_SHUTDOWN = 5
VALIDATION_ERROR = 6
PERMISSION_DENIED = 7
UNSUPPORTED_MESSAGE_TYPE = 8

