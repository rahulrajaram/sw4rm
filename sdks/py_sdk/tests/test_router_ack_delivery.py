"""Consumer-ACK delivery contract tests for the reference Router.

Covers the S2 family of the campaign's crash-conformance invariants:
- S2a: a message accepted by the router survives a process restart and is
  delivered after restart (no lost accepted messages).
- S2b: a consumer that receives a stream item but dies before processing
  gets the message REDELIVERED (the historical yield-time-deletion bug).
- AckDelivery releases the pending row exactly once.
- Lease expiry redelivers unacked rows.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import pytest

pytest.importorskip("grpc")

sys.path.insert(0, str(Path(__file__).parent.parent / "reference-services" / "hive"))

from sw4rm.protos import router_pb2  # noqa: E402
from state_store import RouterStateStore  # noqa: E402


def _db_path(tmp_path: Path) -> str:
    return str(tmp_path / "router.sqlite3")


def _make_envelope(message_id: str):
    from sw4rm.protos import common_pb2

    return common_pb2.Envelope(
        producer_id="producer-1",
        message_type=common_pb2.MessageType.DATA,
        content_type="application/json",
        payload=b'{"hello": "world"}',
        message_id=message_id,
    )


def _make_router(tmp_path: Path, monkeypatch=None):
    
    from router_service import RouterServiceImpl

    router = RouterServiceImpl(db_path=_db_path(tmp_path))
    # Deterministic tests: disable the background sweeper; drive
    # _sweep_expired_leases manually.
    router._sweeper_stop.set()
    return router


def _pb2():
    from sw4rm.protos import router_pb2

    return router_pb2


def _register_consumer(router, agent_id: str):
    router._ensure_agent_queue(agent_id)


class _FakeStreamContext:
    def is_active(self):
        return True


def _drain_stream(router, agent_id: str, count: int = 1, timeout: float = 3.0):
    """Pull up to `count` items from StreamIncoming without acking."""
    import threading

    items = []

    def _run():
        for item in router.StreamIncoming(
            router_pb2.StreamRequest(agent_id=agent_id), _FakeStreamContext()
        ):
            items.append(item)
            if len(items) >= count:
                break

    thread = threading.Thread(target=_run, daemon=True)
    thread.start()
    thread.join(timeout)
    return items


def test_ack_delivery_releases_row_exactly_once(tmp_path: Path) -> None:
    """Ack removes the pending row; a second ack reports not-recorded."""
    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    # producer excluded from targets; register a producer queue too so it has a target
    _register_consumer(router, "producer-1")
    resp = router.SendMessage(
        router_pb2.SendMessageRequest(msg=_make_envelope("m-1")),
        None,
    )
    assert resp.accepted

    items = _drain_stream(router, "consumer-1", count=1)
    assert len(items) == 1
    seq = items[0].seq
    assert seq > 0

    ack = router.AckDelivery(
        router_pb2.DeliveryAckRequest(agent_id="consumer-1", seq=seq), None
    )
    assert ack.recorded is True

    # Second ack for the same seq: unknown row -> not recorded.
    ack2 = router.AckDelivery(
        router_pb2.DeliveryAckRequest(agent_id="consumer-1", seq=seq), None
    )
    assert ack2.recorded is False

    # The row is gone from the store: restart replays nothing for it.
    store = RouterStateStore(_db_path(tmp_path))
    assert all(s != seq for s, _ in store.load_pending_for_agent("consumer-1"))


def test_s2b_unacked_stream_item_is_redelivered_on_reconnect(tmp_path: Path) -> None:
    """The historical loss: receive-but-not-ack then reconnect => redelivery."""
    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    _register_consumer(router, "producer-1")
    resp = router.SendMessage(
        router_pb2.SendMessageRequest(msg=_make_envelope("m-loss")), None
    )
    assert resp.accepted

    items = _drain_stream(router, "consumer-1", count=1)
    assert len(items) == 1, "first delivery should arrive"
    first_seq = items[0].seq

    # Consumer dies WITHOUT acking; a new stream starts (reconnect).
    redelivered = _drain_stream(router, "consumer-1", count=1)
    assert len(redelivered) == 1, "unacked message must be redelivered on reconnect"
    assert redelivered[0].seq == first_seq

    # This time the consumer acks; the message must NOT come back again.
    router.AckDelivery(
        router_pb2.DeliveryAckRequest(agent_id="consumer-1", seq=first_seq), None
    )
    nothing = _drain_stream(router, "consumer-1", count=1, timeout=1.5)
    assert nothing == [], "acked message must not be redelivered"


def test_lease_expiry_redelivers_unacked_rows(tmp_path: Path) -> None:
    """The lease sweeper resets stale in-flight rows for redelivery."""
    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    _register_consumer(router, "producer-1")
    resp = router.SendMessage(
        router_pb2.SendMessageRequest(msg=_make_envelope("m-lease")), None
    )
    assert resp.accepted

    items = _drain_stream(router, "consumer-1", count=1)
    assert len(items) == 1
    seq = items[0].seq

    # No ack. Lease is 30s by default; shrink it and sweep.
    router.delivery_lease_seconds = 0.05
    import time as _t

    _t.sleep(0.1)
    redelivered = router._sweep_expired_leases()
    assert redelivered >= 1

    # Sweeper re-enqueued; a stream delivers it again.
    again = _drain_stream(router, "consumer-1", count=1)
    assert len(again) == 1 and again[0].seq == seq


@pytest.mark.parametrize("agent_id,outcome", [("other-agent", 0), ("", 0), ("consumer-1", 999)])
def test_ack_cannot_release_another_recipient_or_invalid_outcome(tmp_path, agent_id, outcome):
    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    router.SendMessage(router_pb2.SendMessageRequest(msg=_make_envelope("owned")), None)
    item = _drain_stream(router, "consumer-1")[0]
    response = router.AckDelivery(router_pb2.DeliveryAckRequest(
        agent_id=agent_id, seq=item.seq, outcome=outcome), None)
    assert not response.recorded
    assert RouterStateStore(_db_path(tmp_path)).load_pending_for_agent("consumer-1")


def test_expired_ack_cannot_delete_a_pending_redelivery(tmp_path):
    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    router.SendMessage(router_pb2.SendMessageRequest(msg=_make_envelope("expired")), None)
    item = _drain_stream(router, "consumer-1")[0]
    router._state_store.expire_in_flight(0, now=time.time() + 1)
    response = router.AckDelivery(router_pb2.DeliveryAckRequest(
        agent_id="consumer-1", seq=item.seq), None)
    assert not response.recorded
    assert router._state_store.load_pending_for_agent("consumer-1")


def test_s2a_accepted_message_survives_restart(tmp_path: Path) -> None:
    """A message accepted before a kill is delivered after restart."""
    from sw4rm.protos import router_pb2

    router = _make_router(tmp_path)
    _register_consumer(router, "consumer-1")
    _register_consumer(router, "producer-1")
    resp = router.SendMessage(
        router_pb2.SendMessageRequest(msg=_make_envelope("m-restart")), None
    )
    assert resp.accepted
    del router  # simulate process death

    router2 = _make_router(tmp_path)
    items = _drain_stream(router2, "consumer-1", count=1)
    assert len(items) == 1
    assert items[0].msg.message_id == "m-restart"
    # Ack releases it across the restart too.
    router2.AckDelivery(
        router_pb2.DeliveryAckRequest(agent_id="consumer-1", seq=items[0].seq), None
    )
    store = RouterStateStore(_db_path(tmp_path))
    assert store.load_pending_for_agent("consumer-1") == []
