# SW4-013: Security Wire Profile

**Status:** Planning
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §6, §23

> **Planning stage** — this page is authoring notes, not a normative draft. It has no
> MUST/SHALL requirements and no proposed wire fields yet. Treat nothing on this page
> as an API contract; a real draft must be written (and field numbers allocated) before
> adoption.

## Abstract

This extension explores a narrow, optional security wire profile for SW4RM. Its scope is limited to interoperability-visible message fields, negotiation signals, and failure behavior needed when implementations want to expose stronger portable security guarantees on the wire.

## Motivation

The core specification already defines broad security expectations, but most of that content is intentionally implementation- and deployment-specific. A free-standing extension only makes sense if it standardizes something that two independent implementations can actually observe and interoperate on.

## Scope

SW4-013 should only proceed if it stays narrow. Candidate scope includes:

- wire-visible security markers
- optional negotiation of message protection profiles
- canonical failure behavior when required protection is absent or invalid

SW4-013 should not standardize:

- local key management workflows
- deployment-specific PKI operations
- internal authorization engines

## Initial Specification Direction

The first draft must justify why each proposed field or behavior is truly interoperable. If a proposed requirement cannot be observed on the wire or at the gateway boundary, it does not belong in this extension.

## Compatibility

This extension should be optional and additive. Implementations that do not adopt it remain conformant to the core spec.

## References

- [Core Protocol Specification](../spec.md)
- [SW4-015: A2A Gateway Binding](./SW4-015-a2a-gateway-binding.md)
