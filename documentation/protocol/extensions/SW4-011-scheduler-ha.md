# SW4-011: Scheduler High Availability

**Status:** Planning
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §4, §14, §19, §21

> **Planning stage** — this page is authoring notes, not a normative draft. It has no
> MUST/SHALL requirements and no proposed wire fields yet. Treat nothing on this page
> as an API contract; a real draft must be written (and field numbers allocated) before
> adoption.

## Abstract

This extension defines a high-availability profile for the SW4RM Scheduler. The intent is to standardize the safety and failover guarantees required for multi-node production deployments without freezing implementations to a single replication or leader-election stack.

## Motivation

The core specification assumes a single authoritative Scheduler but already identifies HA as future work. Production users need a clearer answer to what must remain safe across failover, replay, and leader transitions.

## Scope

The first draft of SW4-011 should focus on guarantees, including:

- one active scheduler authority at a time
- durable state required for safe failover
- replay and reconciliation expectations
- fencing or equivalent stale-leader protection
- operator-visible failover events and metadata

SW4-011 should not require a specific consensus algorithm or storage product.

## Initial Specification Direction

The proposal should define a minimum HA profile before choosing mechanisms. Candidate implementations may use leases, replicated logs, leader election, or equivalent techniques so long as they satisfy the profile.

## Compatibility

This extension is additive. Single-scheduler deployments remain valid and conformant to the core spec.

## References

- [Core Protocol Specification](../spec.md)
- [SW4-003: Observability](./SW4-003-observability.md)
