# documentation/protocol/messages.md

**Last Updated**: 2026-01-03T00:00:00Z
**Checksum**: [to be computed]
**Lines**: 1-500 (approximate)

## Key Points

- Defines all SW4RM message types and their purpose
- Envelope is the universal container for all messages
- 11 message types: DATA, CONTROL, ACK, HITL, WORKTREE, NEGOTIATION, TOOL_CALL, TOOL_RESULT, TOOL_ERROR, REASONING, CONNECTOR
- Each message type has specific payload schema
- MessageType enum values are stable (never renumbered)
- DATA (2) is the most common type for application payloads
- CONTROL (1) is used for system commands from Scheduler
- ACK (5) confirms receipt and processing status

## Definitions

- **Envelope**: Standard message container with 15 fields
- **MessageType**: Enum classifying message purpose
- **payload**: Binary field containing type-specific content
- **content_type**: MIME type of payload (e.g., application/json)

## Dependencies

- **References**:
  - protos/router.proto (Envelope definition)
  - protos/common.proto (MessageType enum)
- **Referenced by**:
  - documentation/protocol/spec.md
  - documentation/quickstart/first-agent.md
  - sdks/py_sdk/sw4rm/envelope.py

## Verification Required

- [ ] MessageType enum values match protos/common.proto
- [ ] All 11 message types are documented
- [ ] Payload schemas match proto definitions
- [ ] Example payloads are valid JSON/protobuf
