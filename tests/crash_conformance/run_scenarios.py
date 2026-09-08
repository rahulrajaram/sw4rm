# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Executable crash-conformance scenarios (S1/S2a/S2b/S3/S4/S5) + scorecard.

Run:  python3 tests/crash_conformance/run_scenarios.py [--scorecard PATH]

Each scenario drives real reference-service subprocesses over gRPC and
asserts one documented durability invariant. Results land in
artifacts/crash-conformance/crash_scorecard.json (+ .md). Red rows are the point:
the scorecard records honestly which invariants hold today.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "sdks" / "py_sdk"))

from harness import CrashHarness  # noqa: E402
from conformance_contract import (  # noqa: E402
    SCHEMA_VERSION,
    inventory_errors,
    result_errors,
    scorecard_errors,
    summarize,
)
from scenario_s3 import scenario_s3_buffer_write_survives_kill  # noqa: E402
from scenario_s5 import scenario_s5_idempotent_redelivery  # noqa: E402

from sw4rm.protos import common_pb2, negotiation_room_pb2, router_pb2  # noqa: E402
import grpc  # noqa: E402

from sw4rm.protos import (  # noqa: E402
    negotiation_room_pb2_grpc,
    router_pb2_grpc,
)

SCORECARD_PATH = Path(__file__).resolve().parents[2] / "artifacts" / "crash-conformance" / "crash_scorecard.json"


class _StreamCtx:
    def is_active(self):
        return True


def _envelope(message_id: str):
    return common_pb2.Envelope(
        producer_id="producer-1",
        message_type=common_pb2.MessageType.DATA,
        content_type="application/json",
        payload=b'{"x":1}',
        message_id=message_id,
    )


def _proposal(artifact_id: str):
    return negotiation_room_pb2.NegotiationProposal(
        artifact_id=artifact_id,
        negotiation_room_id="crash-room",
        producer_id="producer-1",
    )


def _vote(artifact_id: str, critic_id: str):
    return negotiation_room_pb2.NegotiationVote(
        artifact_id=artifact_id,
        critic_id=critic_id,
        score=8.0,
        confidence=0.9,
        passed=True,
        strengths=[],
        weaknesses=[],
        recommendations=[],
        negotiation_room_id="crash-room",
    )


def _router_stub(port: int):
    channel = grpc.insecure_channel(f"127.0.0.1:{port}")
    return router_pb2_grpc.RouterServiceStub(channel)


def _room_stub(port: int):
    channel = grpc.insecure_channel(f"127.0.0.1:{port}")
    return negotiation_room_pb2_grpc.NegotiationRoomServiceStub(channel)


# ---------------------------------------------------------------- scenarios


def scenario_s2a_accept_survives_kill(h: CrashHarness) -> tuple[str, str]:
    """S2a: a message accepted before SIGKILL is delivered after restart."""
    port = h.start_router()
    stub = _router_stub(port)
    grpc.channel_ready_future(grpc.insecure_channel(f"127.0.0.1:{port}")).result(timeout=10)
    # Register the consumer by opening its stream (this creates the agent queue).
    stream = stub.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
    h.wait_for_router_agent("consumer-1")
    resp = stub.SendMessage(router_pb2.SendMessageRequest(msg=_envelope("s2a-msg")), timeout=10)
    stream.cancel()
    if not resp.accepted:
        return "fail", f"SendMessage not accepted: {resp.reason}"
    h.kill9("router")
    port2 = h.start_router()  # restart over the same DB
    stub2 = _router_stub(port2)
    # Drain the consumer stream; the accepted message must arrive.
    stream2 = stub2.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
    for item in stream2:
        if item.msg.message_id == "s2a-msg":
            return "pass", "accepted message delivered after restart"
        break
    return "fail", "accepted message lost after restart (at-most-once)"


def scenario_s2b_yield_loss_redelivery(h: CrashHarness) -> tuple[str, str]:
    """S2b: consumer receives but does not ack, then reconnects => redelivery."""
    port = h.start_router()
    stub = _router_stub(port)
    # Register the consumer first (its stream creates the agent queue).
    warm = stub.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
    h.wait_for_router_agent("consumer-1")
    warm.cancel()
    resp = stub.SendMessage(router_pb2.SendMessageRequest(msg=_envelope("s2b-msg")), timeout=10)
    assert resp.accepted
    stream = stub.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
    first = next(iter(stream))  # receive WITHOUT ack; break the stream (consumer death)
    stream.cancel()
    time.sleep(0.3)
    # Reconnect: unacked item must be redelivered.
    stream2 = stub.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
    try:
        redelivered = next(iter(stream2))
        if redelivered.seq == first.seq and redelivered.msg == first.msg:
            return "pass", "unacked item redelivered on reconnect (at-least-once)"
        return "fail", f"redelivered seq {redelivered.seq} != original {first.seq}"
    except grpc.RpcError:
        return "fail", "no redelivery after unacked receive (yield-time deletion)"


def scenario_s1_votes_survive_kill(h: CrashHarness) -> tuple[str, str]:
    """S1: proposal + accepted votes survive SIGKILL mid-vote-collection."""
    port = h.start_room()
    stub = negotiation_room_pb2_grpc.NegotiationRoomServiceStub(
        grpc.insecure_channel(f"127.0.0.1:{port}")
    )
    stub.SubmitProposal(
        negotiation_room_pb2.SubmitProposalRequest(proposal=_proposal("s1-art")), timeout=10
    )
    for critic in ("critic-1", "critic-2"):
        stub.SubmitVote(
            negotiation_room_pb2.SubmitVoteRequest(vote=_vote("s1-art", critic)), timeout=10
        )
    h.kill9("room")
    port2 = h.start_room()
    stub2 = negotiation_room_pb2_grpc.NegotiationRoomServiceStub(
        grpc.insecure_channel(f"127.0.0.1:{port2}")
    )
    votes = stub2.GetVotes(
        negotiation_room_pb2.GetVotesRequest(artifact_id="s1-art"), timeout=10
    )
    survived = {v.critic_id for v in votes.votes}
    if survived == {"critic-1", "critic-2"}:
        return "pass", "proposal + 2 votes survived kill mid-vote-collection"
    return "fail", f"expected both votes after restart, got {survived}"


def scenario_s4_corruption_fails_loud(h: CrashHarness) -> tuple[str, str]:
    """S4: a corrupted persistence file fails startup loudly, never silent-empty."""
    room_db = h.room_db
    room_db.write_text("{corrupted!!")
    try:
        h.start_room(db_path=str(room_db))
        return "fail", "service started despite corrupted persistence (silent loss)"
    except RuntimeError as error:
        detail = str(error)
        if ("corrupt" in detail.lower() or "malformed" in detail.lower()
                or "file is not a database" in detail.lower()):
            return "pass", "corrupted persistence blocked startup (fail closed)"
        return "fail", f"startup failed for non-corruption reason: {detail}"


SCENARIOS = [
    ("S2a", "No accepted message is lost across a router kill-restart", scenario_s2a_accept_survives_kill),
    ("S2b", "Unacked stream items are redelivered (at-least-once)", scenario_s2b_yield_loss_redelivery),
    ("S1", "Negotiation state survives kill mid-vote-collection", scenario_s1_votes_survive_kill),
    ("S3", "Confirmed activity-buffer records survive an interrupted snapshot write", scenario_s3_buffer_write_survives_kill),
    ("S4", "Corrupted persistence fails startup loudly (never silent-empty)", scenario_s4_corruption_fails_loud),
    ("S5", "A consumer using the SDK's flushed dedup record suppresses post-crash redelivery", scenario_s5_idempotent_redelivery),
]


def run_all() -> list:
    errors = inventory_errors(tuple(name for name, _, _ in SCENARIOS))
    if errors:
        raise ValueError("; ".join(errors))
    results = []
    for name, invariant, fn in SCENARIOS:
        harness = CrashHarness()
        started = time.monotonic()
        try:
            status, detail = fn(harness)
            errors = result_errors({"scenario": name, "invariant": invariant, "status": status, "detail": detail, "duration_s": 0.0})
            if errors:
                raise ValueError("; ".join(errors))
        except Exception as e:  # distinguish broken execution from a measured red invariant
            status, detail = "error", f"scenario raised: {type(e).__name__}: {e}"
        finally:
            harness.stop_all()
        results.append(
            {
                "scenario": name,
                "invariant": invariant,
                "status": status,
                "detail": detail,
                "duration_s": round(time.monotonic() - started, 2),
            }
        )
        print(f"[{status.upper():4}] {name}: {detail}")
    return results


def write_scorecard(results: list, scorecard_path: Path = SCORECARD_PATH) -> Path:
    scorecard_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "note": "Red rows are expected and informative; this scorecard is the honesty instrument for SW4RM durability claims.",
        "results": results,
        "summary": summarize(results),
    }
    scorecard_path.write_text(json.dumps(payload, indent=2) + "\n")
    md_lines = [
        "# Crash-Conformance Scorecard",
        "",
        f"Generated: {payload['generated_at']}",
        "",
        "| Scenario | Invariant | Status | Detail |",
        "|----------|-----------|--------|--------|",
    ]
    for r in results:
        md_lines.append(
            f"| {r['scenario']} | {r['invariant']} | {r['status'].upper()} | {r['detail']} |"
        )
    md_lines.append("")
    md_lines.append(f"**{payload['summary']['pass']} passing / {payload['summary']['fail']} failing / {payload['summary']['error']} errors** — red rows are the campaign's work queue; errors invalidate the run.")
    scorecard_path.with_suffix(".md").write_text("\n".join(md_lines) + "\n")
    return scorecard_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scorecard", default=str(SCORECARD_PATH))
    args = parser.parse_args()
    results = run_all()
    write_scorecard(results, Path(args.scorecard))
    # Measured red rows are evidence; missing scenarios and harness errors are not.
    errors = scorecard_errors(json.loads(Path(args.scorecard).read_text()))
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
