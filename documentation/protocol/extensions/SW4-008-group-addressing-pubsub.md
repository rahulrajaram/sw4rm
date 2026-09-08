# SW4-008: Group Addressing and Pub/Sub

**Status:** Planning
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §11, §14, §21

> **Planning stage** — this page is authoring notes, not a normative draft. It has no
> MUST/SHALL requirements and no proposed wire fields yet. Treat nothing on this page
> as an API contract; a real draft must be written (and field numbers allocated) before
> adoption.

## Abstract

This extension introduces first-class group addressing and publish/subscribe semantics for SW4RM. It aims to standardize named delivery modes such as one-to-all broadcast, one-of-N group delivery, and topic-style routing without collapsing those behaviors into ambiguous direct messaging.

## Motivation

The core protocol models point-to-point routing well, but multi-recipient communication remains underspecified. Implementations that need group delivery currently must invent private routing conventions, which risks incompatibility in:

- addressing syntax
- delivery expectations
- authorization points
- observability

## Scope

The first draft of SW4-008 should define a compact taxonomy of delivery modes, expected starting with:

- `group_all`
- `group_any`
- `topic`
- `broadcast`

It should also define:

- how publishers address groups
- how subscribers or group members are identified
- which error codes apply when membership or authorization checks fail

SW4-008 should not standardize broker implementation internals.

## Initial Specification Direction

The proposal should make these boundaries explicit:

1. Group identifiers are protected protocol objects, not just routable strings.
2. Authorization is required for publish, subscribe, and receive paths.
3. Delivery guarantees and ordering may differ by delivery mode and must be stated explicitly.
4. The extension should prefer named modes over free-form routing conventions.

## Compatibility

This extension is additive. Existing direct messaging behavior remains unchanged.

## References

- [Core Protocol Specification](../spec.md)
- [SW4-003: Observability](./SW4-003-observability.md)
