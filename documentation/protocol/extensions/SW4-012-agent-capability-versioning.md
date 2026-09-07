# SW4-012: Agent Capability Versioning

**Status:** Rejected
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §14

## Abstract

Proposal to standardize in-place capability and version updates for registered agents without requiring deregister/re-register cycles.

## Verdict: Deferred as Not Currently Needed

This topic was evaluated and is not being advanced as an active extension at this time.

## Why It Is Rejected For Now

1. The current registry model is sufficient for present documented workflows.
2. The team has not identified concrete rollout pain severe enough to justify a new protocol surface.
3. External ecosystems already demonstrate update-in-place patterns, but SW4RM does not yet have evidence that this gap is operationally expensive in practice.

## Revisit Trigger

SW4-012 should only be revived if one or more of the following becomes a recurring issue:

- rolling upgrades cause avoidable downtime or discovery churn
- long-lived sessions repeatedly observe stale capability state
- SDK implementations need incompatible private refresh mechanisms

## Action

No active draft work is planned. The extension ID is retained to document that the idea was considered and consciously deferred.

## References

- [Core Protocol Specification](../spec.md)
