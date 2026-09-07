# SW4-009: Workflow v2 Compensation and Branching

**Status:** Planning
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §17.7

> **Planning stage** — this page is authoring notes, not a normative draft. It has no
> MUST/SHALL requirements and no proposed wire fields yet. Treat nothing on this page
> as an API contract; a real draft must be written (and field numbers allocated) before
> adoption.

## Abstract

This extension evolves the SW4RM workflow model with explicit compensation and richer branching semantics. It is intended to support long-lived, side-effecting workflows that need a portable way to roll back or redirect execution when failures occur.

## Motivation

The current workflow surface provides DAG execution and shared workflow state, but it does not yet define:

- how compensations are declared
- when compensations run
- how compensation failures are handled
- how branch conditions affect execution and recovery

Without those rules, implementations will drift toward incompatible saga-like behaviors.

## Scope

The first draft of SW4-009 should define:

- compensation registration model
- compensation ordering and retry behavior
- branch conditions and branch selection semantics
- terminal states when execution or compensation fails

SW4-009 should not attempt to redesign the entire workflow service.

## Initial Specification Direction

The first normative draft should include at least:

1. A linear compensation example.
2. A branching example with a failed branch.
3. A compensation-failure example that shows final state handling.

## Compatibility

This extension is additive. Existing workflow definitions remain valid but do not gain compensation semantics unless the extension is adopted.

## References

- [Core Protocol Specification](../spec.md)
- [Workflow client documentation](../../clients/workflow.md)
