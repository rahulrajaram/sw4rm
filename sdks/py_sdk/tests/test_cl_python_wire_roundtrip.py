from __future__ import annotations

import subprocess
import tempfile
import textwrap
from pathlib import Path

from sw4rm.protos import common_pb2


REPO_ROOT = Path(__file__).resolve().parents[3]
CODEC_PATH = REPO_ROOT / "sdks" / "cl_sdk" / "src" / "transport" / "protobuf-codec.lisp"


def _run_sbcl_script(script_body: str) -> subprocess.CompletedProcess[str]:
    prelude = textwrap.dedent(
        f"""
        (defpackage #:babel
          (:use #:cl)
          (:export #:string-to-octets #:octets-to-string))

        (in-package #:babel)

        (defun string-to-octets (string &key (encoding :utf-8))
          (declare (ignore encoding))
          (sb-ext:string-to-octets string :external-format :utf-8))

        (defun octets-to-string (octets &key (encoding :utf-8))
          (declare (ignore encoding))
          (sb-ext:octets-to-string octets :external-format :utf-8))

        (defpackage #:sw4rm-sdk (:use #:cl))
        (in-package #:sw4rm-sdk)
        (load "{CODEC_PATH.as_posix()}")
        """
    )
    script = prelude + "\n" + script_body + "\n"

    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as handle:
        handle.write(script)
        script_path = Path(handle.name)

    return subprocess.run(
        ["sbcl", "--script", str(script_path)],
        capture_output=True,
        text=True,
        check=False,
    )


def test_cl_encode_python_decode_envelope_roundtrip() -> None:
    script_body = textwrap.dedent(
        """
        (let* ((payload (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(10 20 30)))
               (env (list :message-id "msg-cl-1"
                          :idempotency-token "idem-1"
                          :producer-id "agent-cl"
                          :correlation-id "corr-cl"
                          :sequence-number 9
                          :retry-count 1
                          :message-type 2
                          :content-type "application/json"
                          :content-length 3
                          :repo-id "repo-a"
                          :worktree-id "wt-a"
                          :hlc-timestamp "HLC:1700000000000:0:test"
                          :ttl-ms 15000
                          :payload payload
                          :state 1
                          :parent-correlation-id "parent-cl"))
               (encoded (encode-envelope env)))
          (loop for b across encoded do (format t "~2,'0X" b))
          (terpri))
        """
    )
    result = _run_sbcl_script(script_body)
    assert result.returncode == 0, result.stderr

    envelope = common_pb2.Envelope()
    envelope.ParseFromString(bytes.fromhex(result.stdout.strip()))

    assert envelope.message_id == "msg-cl-1"
    assert envelope.idempotency_token == "idem-1"
    assert envelope.producer_id == "agent-cl"
    assert envelope.correlation_id == "corr-cl"
    assert envelope.sequence_number == 9
    assert envelope.retry_count == 1
    assert envelope.message_type == 2
    assert envelope.content_type == "application/json"
    assert envelope.content_length == 3
    assert envelope.repo_id == "repo-a"
    assert envelope.worktree_id == "wt-a"
    assert envelope.hlc_timestamp == "HLC:1700000000000:0:test"
    assert envelope.ttl_ms == 15000
    assert envelope.payload == b"\x0a\x14\x1e"
    assert envelope.state == 1
    assert envelope.parent_correlation_id == "parent-cl"


def test_python_encode_cl_decode_envelope_roundtrip() -> None:
    envelope = common_pb2.Envelope(
        message_id="msg-py-1",
        idempotency_token="idem-py",
        producer_id="agent-py",
        correlation_id="corr-py",
        sequence_number=7,
        retry_count=2,
        message_type=3,
        content_type="application/octet-stream",
        content_length=4,
        repo_id="repo-b",
        worktree_id="wt-b",
        hlc_timestamp="HLC:1700000001234:0:test",
        ttl_ms=32000,
        payload=b"\x01\x02\x03\x04",
        state=2,
        parent_correlation_id="parent-py",
    )
    envelope_hex = envelope.SerializeToString().hex().upper()

    script_body = textwrap.dedent(
        f"""
        (defun hex-to-octets (hex)
          (let* ((len (length hex))
                 (out (make-array (/ len 2) :element-type '(unsigned-byte 8))))
            (loop for i from 0 below len by 2
                  for j from 0
                  do (setf (aref out j)
                           (parse-integer hex :start i :end (+ i 2) :radix 16)))
            out))

        (let* ((buf (hex-to-octets "{envelope_hex}"))
               (decoded (decode-envelope buf))
               (payload (getf decoded :payload)))
          (flet ((assert-equal (actual expected label)
                   (unless (equal actual expected)
                     (error "Mismatch ~A: expected ~S got ~S" label expected actual))))
            (assert-equal (getf decoded :message-id) "msg-py-1" "message-id")
            (assert-equal (getf decoded :idempotency-token) "idem-py" "idempotency-token")
            (assert-equal (getf decoded :producer-id) "agent-py" "producer-id")
            (assert-equal (getf decoded :correlation-id) "corr-py" "correlation-id")
            (assert-equal (getf decoded :sequence-number) 7 "sequence-number")
            (assert-equal (getf decoded :retry-count) 2 "retry-count")
            (assert-equal (getf decoded :message-type) 3 "message-type")
            (assert-equal (getf decoded :content-type) "application/octet-stream" "content-type")
            (assert-equal (getf decoded :content-length) 4 "content-length")
            (assert-equal (getf decoded :repo-id) "repo-b" "repo-id")
            (assert-equal (getf decoded :worktree-id) "wt-b" "worktree-id")
            (assert-equal (getf decoded :hlc-timestamp) "HLC:1700000001234:0:test" "hlc-timestamp")
            (assert-equal (getf decoded :ttl-ms) 32000 "ttl-ms")
            (assert-equal (getf decoded :state) 2 "state")
            (assert-equal (getf decoded :parent-correlation-id) "parent-py" "parent-correlation-id")
            (unless (equalp payload #(1 2 3 4))
              (error "Mismatch payload: expected #(1 2 3 4) got ~S" payload))))
        """
    )
    result = _run_sbcl_script(script_body)
    assert result.returncode == 0, result.stderr
