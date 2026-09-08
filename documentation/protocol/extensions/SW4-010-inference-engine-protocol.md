# SW4-010: Inference Engine Protocol

**Status:** Planning
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §9.3, §20, §23

> **Planning stage** — this page is authoring notes, not a normative draft. It has no
> MUST/SHALL requirements and no proposed wire fields yet. Treat nothing on this page
> as an API contract; a real draft must be written (and field numbers allocated) before
> adoption.

## Abstract

This extension defines a black-box contract for inference engine interaction in SW4RM. It standardizes request, response, timeout, fallback, and error expectations for engines that advise agents or schedulers, without standardizing engine internals or model-specific behavior.

## Motivation

The core specification already relies on inference-engine confidence and fallback behavior in several places, but the protocol does not define a stable integration surface. This makes it difficult to build interoperable scheduler and agent implementations around advisory engines.

## Scope

SW4-010 should define only the contract boundary:

- invocation request shape
- advisory response shape
- confidence reporting
- timeout and circuit-breaker behavior
- fallback expectations when engines are unavailable

SW4-010 must treat inference engines as opaque components. It must not encode prompt formats, reasoning traces, model classes, or any LLM-specific assumptions.

## Initial Specification Direction

The first draft should answer:

1. Which fields are required for engines to make scheduling or conflict recommendations.
2. Whether confidence semantics must be normalized across engine types.
3. How unavailability, invalid output, or slow responses are surfaced to callers.

## Compatibility

This extension is additive and should preserve the core spec's conservative fallback behavior when no inference engine is present.

## References

- [Core Protocol Specification](../spec.md)
- [SW4-003: Observability](./SW4-003-observability.md)
