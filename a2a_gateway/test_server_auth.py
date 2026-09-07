"""Regression tests for A2A gateway authentication and identity repair.

Covers the campaign's Slice B R1 findings:
- unauthenticated POST must be rejected with 401 before any dispatch
- caller-supplied `sw4rm.sender` metadata must not set the envelope
  producer_id (server-derived identity only)
- oversized Content-Length must be rejected with 413 before reading the body
"""
from __future__ import annotations

import threading
import unittest
from unittest import mock

from a2a_gateway import server as server_module
from a2a_gateway.adapter import A2AToSW4RMAdapter
from a2a_gateway.server import (
    MAX_BODY_BYTES,
    A2AHTTPHandler,
    make_http_handler,
    resolve_subject,
    start_http_server,
)


class _FakeTaskStore:
    """Minimal task store so the adapter can create tasks without state."""

    def create_task(self, target_agent_id, message, context_id=None):
        return {"id": "task-1", "status": "SUBMITTED"}

    def update_state(self, task_id, state, message=None):
        return None


class _RecordingRouter:
    def __init__(self):
        self.envelopes = []

    def send_message(self, envelope):
        self.envelopes.append(envelope)
        return {"accepted": True}


def _make_adapter():
    adapter = mock.create_autospec(A2AToSW4RMAdapter, instance=True)
    adapter.captured = []

    def real_send_message(message, target_agent_id, context_id=None, producer_id="a2a-gateway"):
        from a2a_gateway.adapter import a2a_message_to_sw4rm_envelope

        envelope = a2a_message_to_sw4rm_envelope(
            message=message,
            target_agent_id=target_agent_id,
            task_id="task-1",
            producer_id=producer_id,
        )
        adapter.captured.append(envelope)
        return {"id": "task-1", "status": "SUBMITTED"}

    adapter.send_message.side_effect = real_send_message
    adapter.get_agent_card.return_value = {"name": "a2a-gateway"}
    return adapter


def _post(handler_cls, port, body: bytes, headers: dict, path: str = "/") -> tuple[int, dict, _RecordingRouter]:
    import json as jsonlib
    import urllib.request
    from urllib.error import HTTPError

    router = _RecordingRouter()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}", data=body, headers=headers, method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status, payload = response.status, jsonlib.loads(response.read())
    except HTTPError as error:
        status, payload = error.code, jsonlib.loads(error.read())
    return status, payload, router


class ResolveSubjectTests(unittest.TestCase):
    def test_valid_token_maps_to_subject(self):
        tokens = {"secret-token": "caller-a"}
        self.assertEqual(resolve_subject("Bearer secret-token", tokens), "caller-a")

    def test_missing_or_malformed_header_is_unauthenticated(self):
        tokens = {"secret-token": "caller-a"}
        self.assertIsNone(resolve_subject(None, tokens))
        self.assertIsNone(resolve_subject("Basic abc", tokens))
        self.assertIsNone(resolve_subject("Bearer ", tokens))

    def test_unknown_token_is_unauthenticated(self):
        self.assertIsNone(resolve_subject("Bearer nope", {"secret": "caller-a"}))

    def test_no_tokens_configured_rejects_everything(self):
        self.assertIsNone(resolve_subject("Bearer anything", None))


class GatewayAuthTests(unittest.TestCase):
    """End-to-end HTTP tests against a real loopback server."""

    def setUp(self):
        self.adapter = _make_adapter()
        self.tokens = {"test-token": "authenticated-caller"}
        self.server = start_http_server(
            self.adapter, port=0, host="127.0.0.1", auth_tokens=self.tokens,
        )
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def _send_message_body(self, spoofed_sender: bool = True) -> bytes:
        import json as jsonlib

        metadata = {"sw4rm.target_agent": "victim-agent"}
        if spoofed_sender:
            metadata["sw4rm.sender"] = "trusted-agent-1"
        message = {"role": "user", "parts": [{"text": {"text": "hi"}}], "metadata": metadata}
        return jsonlib.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "SendMessage",
            "params": {"message": message},
        }).encode()

    def test_unauthenticated_post_returns_401_and_never_dispatches(self):
        status, payload, _ = _post(A2AHTTPHandler, self.port, self._send_message_body(), {})
        self.assertEqual(status, 401)
        self.assertEqual(payload["error"]["code"], -32000)
        self.adapter.send_message.assert_not_called()

    def test_wrong_token_returns_401(self):
        status, payload, _ = _post(
            A2AHTTPHandler, self.port, self._send_message_body(),
            {"Authorization": "Bearer wrong-token"},
        )
        self.assertEqual(status, 401)
        self.adapter.send_message.assert_not_called()

    def test_authenticated_caller_cannot_spoof_producer_identity(self):
        status, payload, _ = _post(
            A2AHTTPHandler, self.port, self._send_message_body(),
            {"Authorization": "Bearer test-token"},
        )
        self.assertEqual(status, 200)
        self.adapter.send_message.assert_called_once()
        kwargs = self.adapter.send_message.call_args.kwargs
        self.assertEqual(kwargs["producer_id"], "authenticated-caller")
        # The spoofed sw4rm.sender metadata must not reach the envelope.
        self.assertEqual(self.adapter.captured[0]["producer_id"], "authenticated-caller")

    def test_oversized_content_length_returns_413_without_reading_body(self):
        # Raw socket: urllib would overwrite the Content-Length header from
        # the actual body size, and we need a declared size above the cap.
        import socket

        sock = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        try:
            request = (
                f"POST / HTTP/1.1\r\nHost: 127.0.0.1:{self.port}\r\n"
                f"Authorization: Bearer test-token\r\n"
                f"Content-Length: {MAX_BODY_BYTES + 1}\r\n"
                f"Connection: close\r\n\r\n"
            ).encode()
            sock.sendall(request)
            response = b""
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                response += chunk
        finally:
            sock.close()
        self.assertIn(b" 413 ", response.split(b"\r\n")[0], response[:80])
        self.assertIn(b"exceeds", response)

    def test_single_token_env_maps_to_default_producer(self):
        with mock.patch.dict("os.environ", {"A2A_API_KEY": "env-key"}, clear=False):
            tokens = server_module.load_auth_tokens()
        self.assertEqual(tokens, {"env-key": "a2a-gateway"})


class RefuseExternalBindTests(unittest.TestCase):
    def test_non_loopback_bind_without_tokens_is_refused(self):
        with self.assertRaises(SystemExit):
            start_http_server(_make_adapter(), port=0, host="0.0.0.0", auth_tokens=None)

    def test_non_loopback_bind_with_tokens_is_allowed(self):
        server = start_http_server(
            _make_adapter(), port=0, host="0.0.0.0", auth_tokens={"t": "s"},
        )
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    unittest.main()
