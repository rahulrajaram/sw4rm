# Crash-Injection Conformance Suite

Executable checks of SW4RM's durability claims. The service scenarios use
real gRPC and subprocesses. Each row states its actual failure boundary;
reconnecting a stream and killing a process are different experiments.

## Scenarios

| ID | Invariant | Method |
|----|-----------|--------|
| S1 | Negotiation state (proposal + votes) survives a kill during vote collection | SIGKILL the room mid-votes; restart; assert votes replay |
| S2a | No accepted message is lost across a router kill-restart | accept → SIGKILL → restart → assert delivery |
| S2b | Delivery is at-least-once: unacked stream items are redelivered | receive-without-ack → reconnect → assert redelivery (the historical yield-time-deletion bug) |
| S3 | Previously flushed activity records survive an interrupted snapshot write | synchronize a real writer at the write boundary → SIGKILL → reopen the persisted buffer in a fresh process |
| S4 | Corrupted persistence fails startup loudly, never silent-empty | corrupt the DB → assert startup refuses |
| S5 | A consumer using the SDK's flushed idempotency record suppresses a redelivered side effect | apply effect and flush completion record → SIGKILL before delivery ACK → restart consumer → verify redelivery, one effect, and ACK |

S3 exercises process death on the host filesystem, not power loss. S5 uses
`PersistentActivityBuffer.get_by_idempotency_token` explicitly within its
configured retention window. It covers death after both the effect and the
completion record have been persisted. It does not make those two writes
atomic, cover death between them, or establish automatic exactly-once
execution by `RouterClient` or `MessageProcessor`.

## Run

```bash
python3 tests/crash_conformance/run_scenarios.py          # prints + writes scorecard
pytest tests/crash_conformance -q                         # pytest wrapper (same scenarios)
```

## Scorecard

Results are written to `artifacts/crash-conformance/crash_scorecard.{json,md}` (gitignored; CI uploads a fresh copy).
The schema-v2 scorecard must contain S1, S2a, S2b, S3, S4, and S5 exactly
once, with a matching summary. A `pass` means the stated invariant held;
a `fail` means it was measured and did not hold. Both are valid evidence.
An `error` means the harness could not measure the invariant and makes the
command fail. Unexpected child exceptions and malformed or contradictory
verdict markers also fail pytest. A passing pytest suite therefore proves
that the required experiments produced valid verdicts; consult the fresh
scorecard to see which invariants passed.

Python CI runs the crash harness and uploads a fresh scorecard.
