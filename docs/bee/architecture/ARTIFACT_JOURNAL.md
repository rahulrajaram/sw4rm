# Artifact Journal

This document specifies the Artifact Journal: a durable, append-only record of negotiation artifacts owned by the Scheduler. It complements the operational Activity Buffer by storing versioned contracts, diffs, and decision reports.

## Scope
- Persist artifacts per `negotiation_id` for audit, rollbacks, and operator inspection.
- Provide a stable file layout for local DevCore and a future RPC surface for standalone Scheduler deployments.
- Remain write-only (append/replace per version), never mutating prior versions.

Non-goals: global query/indexing, cross-host replication, or schema enforcement beyond basic JSON shape checks.

## Ownership
- Owner: Scheduler. Policy, scoring, rounds, and decisions are Scheduler-owned; the Journal co-resides with these responsibilities.

## Data Model
- Keys: `negotiation_id` (string), `version` (u32), optional `from`/`to` versions for diffs.
- Artifacts:
  - Contract: `contract_v{N}.json` — versioned JSON contract snapshot.
  - Diff: `diff_v{N-1}_to_v{N}.json` — structured JSON diff between adjacent versions.
  - Decision Report: `decision_report.json` — final acceptance/stop rationale, scores, stop reason.

## File Layout (DevCore)
- Base dir: `$BEE_HOME/artifacts/` (defaults to `~/.config/bee/artifacts/`).
- Per negotiation subdir: `$BEE_HOME/artifacts/<negotiation_id>/`.
  - Files:
    - `contract_v1.json`, `contract_v2.json`, ...
    - `diff_v1_to_v2.json`, ...
    - `decision_report.json`

## Interfaces
- Local (DevCore): minimal file-backed API, used by CLI stubs.
  - AppendContract(neg_id, v, bytes)
  - AppendDiff(neg_id, from, to, bytes)
  - WriteDecision(neg_id, bytes)
  - List(neg_id) -> filenames
  - Read(neg_id, filename) -> bytes

- Future RPC (Scheduler service):
  - Append(List/Show) gRPC methods guarded by scheduler policy; Bee CLI becomes a client.

## CLI
- `bee artifact list <negotiation_id>` — lists artifact filenames.
- `bee artifact show <negotiation_id> [filename]` — prints file content or summarizes available files.
  - Shell parity can be added later as `/artifact ...` if needed.

## Notes
- The Activity Buffer remains the operational transcript; artifacts live in the Journal only.
- File writes are atomic per file (write to temp then rename) where supported.
- Backups are simple directory copies per negotiation id.
