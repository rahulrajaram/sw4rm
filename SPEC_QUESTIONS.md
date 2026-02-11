# SW4RM Spec Clarifications Needed

Questions arising from the SDK audit that require spec-lead decisions before implementation.

---

## Q14: Idempotency Token Canonicalization Algorithm

**Spec ref:** Section 12 (Idempotency)

**Problem:** All four SDKs produce idempotency tokens in the format `{producer_id}:{operation}:{sha256_prefix_16}`, but they differ in how the input parameters are canonicalized before hashing:

| SDK | Canonicalization method |
|-----|------------------------|
| Python | `json.dumps(params, sort_keys=True, separators=(',', ':'))` — SDK handles sorting |
| Rust | `serde_json::to_string(params)` — serde sorts keys by default |
| JS/TS | Caller must pass pre-serialized `canonical_bytes: Uint8Array` — SDK does NOT canonicalize |
| CL | Not yet implemented beyond error handling for duplicates |

**Risk:** If a Python agent and a JS agent both send the same logical operation with the same parameters, they may produce different idempotency tokens because the canonicalization differs. This breaks cross-SDK deduplication.

**Proposed resolution:** Define a normative canonicalization algorithm in the spec:

1. Serialize parameters as JSON with keys sorted lexicographically (recursive)
2. Use compact encoding (no whitespace): `separators=(',', ':')`
3. Unicode: NFC normalization, escape non-ASCII as `\uXXXX`
4. Numbers: no trailing zeros, no leading `+`
5. Token format: `{producer_id}:{operation_type}:{sha256(canonical_json)[0:16]}`

**Action needed:** Spec-lead to draft normative text for Section 12, then align JS SDK to handle canonicalization internally.

---

## Q15: Activity Buffer (Section 10) vs Inbound Message Buffer (Section 13)

**Spec ref:** Section 10 (Activity Buffer), Section 13 (Buffers and Back-Pressure)

**Problem:** The spec references both an "Activity Buffer" (Section 10) and "inbound message buffer" concepts (Section 13 — back-pressure metrics like `INBOUND_QUEUE_DEPTH`). It is unclear whether these are the same buffer or two distinct buffers.

**Finding from audit:** All four SDKs implement a **single unified ActivityBuffer** that tracks both inbound and outbound messages using a `direction` field ("in" / "out"). There is no separate inbound-only buffer.

| SDK | Implementation | Direction tracking |
|-----|---------------|-------------------|
| Python | `ActivityBuffer` / `PersistentActivityBuffer` | `record.direction` ("in"/"out") |
| Rust | `ActivityBuffer` | `record.direction` ("in"/"out") |
| JS/TS | `PersistentActivityBuffer` | `record.direction` ("in"/"out") |
| CL | `activity-buffer` | Per-entry `task-id` tracking |

**Question:** Is this correct? Should the spec clarify that:
- Section 10's "Activity Buffer" is the unified buffer for all message tracking
- Section 13's "inbound queue" metrics refer to the inbound subset of the same buffer (filtered by direction="in")

**Action needed:** Spec-lead to add a clarifying note in Section 10 or Section 13 confirming the single-buffer design.

---

## Q16: `activity_buffer_full` vs `buffer_full` Error Code Naming

**Spec ref:** Section 10, Section 11 (ErrorCode enum)

**Problem:** The spec text appears to use both `activity_buffer_full` (descriptive prose) and `BUFFER_FULL` (enum constant) when referring to the same error condition.

**Finding from audit:** All SDKs and the protobuf definition consistently use `BUFFER_FULL = 1`:

| Source | Name | Value |
|--------|------|-------|
| `protos/common.proto` | `BUFFER_FULL` | 1 |
| Python `constants.py` | `BUFFER_FULL` | 1 |
| Rust `constants.rs` | `error_code::BUFFER_FULL` | 1 |
| JS/TS `errorMapping.ts` | `ErrorCode.BUFFER_FULL` | 1 |
| CL `constants.lisp` | `+buffer-full+` | 1 |

**Conclusion:** This is already resolved in implementation. The canonical name is `BUFFER_FULL` (value 1). Any spec prose using `activity_buffer_full` should be updated to reference `BUFFER_FULL` for consistency.

**Action needed:** Spec-lead to grep spec text for `activity_buffer_full` and replace with `BUFFER_FULL` references. Low-effort editorial fix.
