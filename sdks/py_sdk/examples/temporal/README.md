# Temporal approval reference skeleton

This is a documented, optional reference skeleton showing how a Temporal
workflow can collect approval votes. It is not runtime-verified in this
repository: `temporalio` is not installed and is deliberately not a core or
optional SDK dependency.

The workflow demonstrates a `@workflow.defn` class, a `@workflow.run` method,
an idempotent `@workflow.signal` vote handler, `workflow.wait_condition` with
a durable timeout, and `workflow.all_handlers_finished` before completion.
The policy package remains stdlib-only; Temporal provides durable execution,
signals, and timers, while SW4RM provides quorum, aggregation, and escalation
semantics. A timeout returns `ESCALATED_TO_HITL` with `timed_out=True`; a
completed quorum produces the neutral policy's `APPROVED`,
`REVISION_REQUESTED`, or `ESCALATED_TO_HITL` result. This is source-contract
verified only in this repository, not runtime-verified against Temporal.

To run it, separately provision a supported `temporalio` release, a Temporal
server, and a worker that registers `ApprovalWorkflow`. Those setup steps are
intentionally outside the default SDK install and test lanes.

API references:

- [Temporal Python SDK workflow documentation](https://github.com/temporalio/sdk-python#usage)
- [Temporal Python SDK timers, conditions, and testing](https://github.com/temporalio/sdk-python#timers)
- [Official signal workflow sample](https://github.com/temporalio/samples-python/blob/main/message_passing/introduction/workflows.py)
