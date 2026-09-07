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

"""S5 consumer idempotency evidence for the crash-conformance scorecard.

The consumer uses the SDK's ``PersistentActivityBuffer`` token index to
recognize a completed logical operation after a real gRPC redelivery.  The
test deliberately kills the consumer after its side effect and durable SDK
record have been flushed, but before ``AckDelivery``.  This demonstrates the
narrow SDK-assisted window; it does not claim an atomic transaction between
an arbitrary external side effect and the activity-buffer record.
"""

from __future__ import annotations

import json
import hashlib
import signal
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Any

import grpc

from harness import read_child_line
from sw4rm.protos import common_pb2, router_pb2, router_pb2_grpc


_EVENT_PREFIX = "S5_EVENT "
_READ_TIMEOUT_S = 20.0


def _child_source() -> str:
    """Return the isolated consumer program run in fresh interpreters."""
    return textwrap.dedent(
        r'''
        from __future__ import annotations

        import json
        import hashlib
        import os
        import time
        from pathlib import Path

        import grpc

        from sw4rm import constants as C
        from sw4rm.activity_buffer import PersistentActivityBuffer, is_terminal_state
        from sw4rm.persistence import JSONFilePersistence
        from sw4rm.protos import router_pb2, router_pb2_grpc

        def event(kind, **fields):
            print("S5_EVENT " + json.dumps({"kind": kind, **fields}, sort_keys=True), flush=True)

        def envelope_digest(message):
            return hashlib.sha256(message.SerializeToString(deterministic=True)).hexdigest()

        port = int(os.environ["SW4RM_S5_ROUTER_PORT"])
        agent_id = os.environ["SW4RM_S5_AGENT_ID"]
        expected_token = os.environ["SW4RM_S5_TOKEN"]
        buffer_path = Path(os.environ["SW4RM_S5_BUFFER_PATH"])
        side_effect_path = Path(os.environ["SW4RM_S5_SIDE_EFFECT_PATH"])

        # This is the real SDK persistence/dedup implementation.  The child
        # intentionally does not implement a replacement token map or dedup
        # policy of its own.
        buffer = PersistentActivityBuffer(
            persistence=JSONFilePersistence(str(buffer_path)),
            dedup_window_s=3600,
        )
        channel = grpc.insecure_channel(f"127.0.0.1:{port}")
        stub = router_pb2_grpc.RouterServiceStub(channel)
        stream = stub.StreamIncoming(router_pb2.StreamRequest(agent_id=agent_id), timeout=60)
        event("READY")

        for item in stream:
            message = item.msg
            token = message.idempotency_token
            event(
                "RECEIVED",
                message_id=message.message_id,
                seq=int(item.seq),
                token=token,
                envelope_digest=envelope_digest(message),
            )
            if token != expected_token:
                event("ERROR", detail=f"unexpected idempotency token {token!r}")
                raise SystemExit(2)

            # Deduplication is explicitly SDK-assisted.  A terminal record
            # survives the child restart and suppresses the second side effect.
            existing = buffer.get_by_idempotency_token(token)
            if existing is not None and is_terminal_state(
                int(existing.envelope.get("state", C.ENVELOPE_STATE_UNSPECIFIED))
            ):
                event(
                    "DEDUPED",
                    message_id=message.message_id,
                    seq=int(item.seq),
                    original_message_id=existing.message_id,
                )
                response = stub.AckDelivery(
                    router_pb2.DeliveryAckRequest(
                        agent_id=agent_id,
                        seq=int(item.seq),
                        message_id=message.message_id,
                    ),
                    timeout=10,
                )
                event("ACKED", recorded=bool(response.recorded), seq=int(item.seq))
                raise SystemExit(0)

            # Deliberately model an external side effect as an append followed
            # by fsync.  It occurs before the SDK record is written and flushed.
            with side_effect_path.open("a", encoding="utf-8") as effect:
                effect.write(message.message_id + "\n")
                effect.flush()
                os.fsync(effect.fileno())

            envelope = {
                "message_id": message.message_id,
                "idempotency_token": token,
                "producer_id": message.producer_id,
                "correlation_id": message.correlation_id,
                "sequence_number": int(message.sequence_number),
                "retry_count": int(message.retry_count),
                "message_type": int(message.message_type),
                "content_type": message.content_type,
                "content_length": int(message.content_length),
                "repo_id": message.repo_id,
                "worktree_id": message.worktree_id,
                "hlc_timestamp": message.hlc_timestamp,
                "ttl_ms": int(message.ttl_ms),
                "state": C.FULFILLED_ENVELOPE,
                "payload": bytes(message.payload),
            }
            buffer.record_incoming(envelope)
            buffer.flush()
            event(
                "SIDE_EFFECT_FLUSHED",
                message_id=message.message_id,
                seq=int(item.seq),
                token=token,
                buffer_path=str(buffer_path),
            )

            # The parent kills this process at exactly this synchronization
            # point, before the delivery ACK can be sent.
            while True:
                time.sleep(1)
        ''',
    )


def _event_line(
    proc: subprocess.Popen[bytes], kind: str, timeout: float = _READ_TIMEOUT_S,
    *, alternate: str | None = None,
) -> dict[str, Any]:
    """Read one named child event, returning a bounded diagnostic on failure."""
    deadline = time.monotonic() + timeout
    diagnostics: list[str] = []
    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        line = read_child_line(proc, timeout=remaining)
        line = line.rstrip()
        if not line.startswith(_EVENT_PREFIX):
            diagnostics.append(line[-300:])
            continue
        try:
            event = json.loads(line[len(_EVENT_PREFIX):])
        except json.JSONDecodeError:
            diagnostics.append(line[-300:])
            continue
        if event.get("kind") == kind or (alternate is not None and event.get("kind") == alternate):
            return event
        if event.get("kind") == "ERROR":
            raise RuntimeError(str(event.get("detail", "consumer reported an error")))
        diagnostics.append(line[-300:])
    status = f"exit={proc.poll()}" if proc.poll() is not None else "still running"
    raise RuntimeError(f"timed out waiting for S5 {kind} event ({status}); output={diagnostics[-4:]}")


def _stop_child(proc: subprocess.Popen[bytes] | None) -> None:
    """Reap a consumer child even when the scenario fails mid-handshake."""
    if proc is None or proc.poll() is not None:
        return
    proc.send_signal(signal.SIGKILL)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=10)


def _close_child(proc: subprocess.Popen[bytes] | None) -> None:
    """Kill/reap and close all pipes for a consumer child."""
    _stop_child(proc)
    if proc is None:
        return
    for stream in (proc.stdout, proc.stderr):
        if stream is not None:
            stream.close()


def _consumer_env(h: Any, port: int, token: str, buffer_path: Path, side_effect_path: Path) -> dict[str, str]:
    env = h._env()
    env.update(
        {
            "SW4RM_S5_ROUTER_PORT": str(port),
            "SW4RM_S5_AGENT_ID": "consumer-1",
            "SW4RM_S5_TOKEN": token,
            "SW4RM_S5_BUFFER_PATH": str(buffer_path),
            "SW4RM_S5_SIDE_EFFECT_PATH": str(side_effect_path),
        }
    )
    return env


def scenario_s5_idempotent_redelivery(h: Any) -> tuple[str, str]:
    """S5: a flushed SDK completion suppresses a redelivered side effect."""
    child: subprocess.Popen[bytes] | None = None
    restarted: subprocess.Popen[bytes] | None = None
    channel: grpc.Channel | None = None
    try:
        port = h.start_router()
        channel = grpc.insecure_channel(f"127.0.0.1:{port}")
        stub = router_pb2_grpc.RouterServiceStub(channel)

        # Register the consumer queue before launching the consumer process.
        warm = stub.StreamIncoming(router_pb2.StreamRequest(agent_id="consumer-1"), timeout=10)
        h.wait_for_router_agent("consumer-1", timeout=5)
        warm.cancel()

        token = "producer-1:crash_s5:side-effect-once"
        message_id = "s5-original-attempt"
        buffer_path = h.workdir / "s5-consumer-activity.json"
        side_effect_path = h.workdir / "s5-side-effects.log"
        script_path = h.workdir / "s5_consumer.py"
        script_path.write_text(_child_source(), encoding="utf-8")
        env = _consumer_env(h, port, token, buffer_path, side_effect_path)
        original_envelope = common_pb2.Envelope(
            producer_id="producer-1",
            message_type=common_pb2.MessageType.DATA,
            content_type="application/json",
            payload=b'{"operation":"side-effect-once"}',
            message_id=message_id,
            idempotency_token=token,
        )
        original_digest = hashlib.sha256(
            original_envelope.SerializeToString(deterministic=True)
        ).hexdigest()

        child = subprocess.Popen(
            [sys.executable, str(script_path)],
            cwd=str(h.workdir),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            bufsize=0,
        )
        _event_line(child, "READY")

        response = stub.SendMessage(
            router_pb2.SendMessageRequest(
                msg=original_envelope
            ),
            timeout=10,
        )
        if not response.accepted:
            return "fail", f"S5 SendMessage rejected: {response.reason}"

        first = _event_line(child, "RECEIVED")
        flushed = _event_line(child, "SIDE_EFFECT_FLUSHED")
        if first.get("message_id") != message_id or flushed.get("message_id") != message_id:
            return "fail", f"first delivery envelope mismatch: received={first}, flushed={flushed}"
        if first.get("envelope_digest") != original_digest:
            return "fail", f"first delivery envelope digest changed: sent={original_digest}, got={first}"
        if first.get("seq") != flushed.get("seq"):
            return "fail", f"first delivery seq changed before flush: received={first}, flushed={flushed}"

        original_seq = int(first["seq"])
        _stop_child(child)
        if child.returncode != -signal.SIGKILL:
            return "fail", f"first consumer did not terminate by SIGKILL: returncode={child.returncode}"

        # A fresh interpreter reloads the SDK buffer from disk and reconnects
        # to the same real gRPC router; the router must redeliver the same row.
        restarted = subprocess.Popen(
            [sys.executable, str(script_path)],
            cwd=str(h.workdir),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            bufsize=0,
        )
        _event_line(restarted, "READY")
        redelivered = _event_line(restarted, "RECEIVED")
        if redelivered.get("message_id") != message_id:
            return "fail", f"redelivery envelope changed: original={message_id}, got={redelivered}"
        if redelivered.get("envelope_digest") != original_digest:
            return "fail", f"redelivery envelope digest changed: sent={original_digest}, got={redelivered}"
        if redelivered.get("envelope_digest") != first.get("envelope_digest"):
            return "fail", f"redelivery digest differs from original delivery: first={first}, second={redelivered}"
        if int(redelivered.get("seq", -1)) != original_seq:
            return "fail", f"redelivery seq changed: original={original_seq}, got={redelivered}"

        deduped = _event_line(restarted, "DEDUPED", alternate="SIDE_EFFECT_FLUSHED")
        if deduped.get("kind") == "SIDE_EFFECT_FLUSHED":
            return "fail", "restarted consumer repeated the side effect instead of recognizing its flushed SDK completion"
        if (int(deduped.get("seq", -1)) != original_seq
                or deduped.get("message_id") != message_id
                or deduped.get("original_message_id") != message_id):
            return "fail", f"SDK dedup event did not identify original delivery: {deduped}"
        acked = _event_line(restarted, "ACKED")
        if not bool(acked.get("recorded")):
            return "fail", f"redelivery ACK was not recorded: {acked}"
        restarted.wait(timeout=10)
        if restarted.returncode != 0:
            return "fail", f"restarted consumer exited unsuccessfully: returncode={restarted.returncode}"

        effects = side_effect_path.read_text(encoding="utf-8").splitlines() if side_effect_path.exists() else []
        effect_count = sum(1 for effect in effects if effect == message_id)
        if effect_count != 1:
            return "fail", f"SDK dedup did not hold: side effect count for {message_id}={effect_count}, effects={effects}"

        # The consumer ACK released the row. A duplicate ACK must therefore be
        # rejected by the router, providing direct evidence of ACK behavior.
        late_ack = stub.AckDelivery(
            router_pb2.DeliveryAckRequest(
                agent_id="consumer-1",
                seq=original_seq,
                message_id=message_id,
            ),
            timeout=10,
        )
        if late_ack.recorded:
            return "fail", "router accepted a second ACK for the redelivered row"

        return (
            "pass",
            "same envelope/seq redelivered after consumer SIGKILL; SDK PersistentActivityBuffer deduped the completed token, side effect count=1, and ACK released the row",
        )
    finally:
        _close_child(child)
        _close_child(restarted)
        if channel is not None:
            channel.close()


__all__ = ["scenario_s5_idempotent_redelivery"]
