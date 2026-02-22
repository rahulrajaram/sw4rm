#!/usr/bin/env python3
"""Bounded CL codec integration test against reference Python gRPC services.

This harness validates practical end-to-end flows for tranche I59 and I60:
1) CL codec encodes RegisterAgentRequest bytes
2) Bytes are sent to live reference RegistryService via raw gRPC
3) CL codec decodes RegisterAgentResponse bytes
4) CL codec encodes Router SendMessageRequest bytes
5) Bytes are sent to live reference RouterService via raw gRPC
6) CL codec decodes SendMessageResponse + streamed StreamItem bytes
7) `--tls-smoke` also runs TLS secure transport smoke with self-signed certificate and optional CL transport probe.

The CL gRPC runtime is not loaded for the base I59 flow (requires external
Lisp deps). TLS mode optionally adds a CL transport probe when `--require-cl-probe`
is set.
"""

from __future__ import annotations

import argparse
import os
import queue
import socket
import subprocess
import sys
from typing import Any
import tempfile
import textwrap
import threading
import time
from dataclasses import dataclass
from pathlib import Path

import grpc


REPO_ROOT = Path(__file__).resolve().parents[3]
PY_SDK_PATH = REPO_ROOT / "sdks" / "py_sdk"
CODEC_PATH = REPO_ROOT / "sdks" / "cl_sdk" / "src" / "transport" / "protobuf-codec.lisp"
GRPC_FFI_PATH = REPO_ROOT / "sdks" / "cl_sdk" / "src" / "transport" / "grpc-ffi.lisp"
GRPC_TRANSPORT_PATH = REPO_ROOT / "sdks" / "cl_sdk" / "src" / "transport" / "grpc-transport.lisp"
REGISTRY_SERVICE_PATH = (
    REPO_ROOT / "sdks" / "py_sdk" / "reference-services" / "hive" / "registry_service.py"
)
ROUTER_SERVICE_PATH = (
    REPO_ROOT / "sdks" / "py_sdk" / "reference-services" / "hive" / "router_service.py"
)

if str(PY_SDK_PATH) not in sys.path:
    sys.path.insert(0, str(PY_SDK_PATH))

from sw4rm.protos import registry_pb2, registry_pb2_grpc, router_pb2, router_pb2_grpc  # noqa: E402


@dataclass
class ServiceProc:
    name: str
    proc: subprocess.Popen[str]


def _find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        return int(sock.getsockname()[1])


def _generate_self_signed_cert(cert_path: Path, key_path: Path, hostname: str = "localhost") -> None:
    try:
        from cryptography import x509
        from cryptography.hazmat.backends import default_backend
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID
    except Exception as exc:
        raise RuntimeError(
            "TLS smoke test requires cryptography package for self-signed cert generation"
        ) from exc

    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend(),
    )
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SW4RM Test"),
            x509.NameAttribute(NameOID.COMMON_NAME, hostname),
        ]
    )
    certificate = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(__import__("datetime").datetime.utcnow())
        .not_valid_after(__import__("datetime").datetime.utcnow().replace(year=3000))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), critical=False)
        .sign(key, hashes.SHA256(), default_backend())
    )

    cert_path.write_bytes(certificate.public_bytes(encoding=serialization.Encoding.PEM))
    key_path.write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )


def _sbcl_prelude() -> str:
    return textwrap.dedent(
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

        (defun hex-to-octets (hex)
          (let* ((len (length hex))
                 (out (make-array (/ len 2) :element-type '(unsigned-byte 8))))
            (loop for i from 0 below len by 2
                  for j from 0
                  do (setf (aref out j)
                           (parse-integer hex :start i :end (+ i 2) :radix 16)))
            out))
        """
    )


def _run_sbcl(script_body: str) -> str:
    script = _sbcl_prelude() + "\n" + script_body + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as handle:
        handle.write(script)
        script_path = Path(handle.name)
    try:
        completed = subprocess.run(
            ["sbcl", "--script", str(script_path)],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
    finally:
        try:
            script_path.unlink()
        except OSError:
            pass

    if completed.returncode != 0:
        raise RuntimeError(
            "SBCL script failed\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}\n"
            f"script:\n{script_body}"
        )
    return completed.stdout.strip()


def _sbcl_transport_prelude() -> str:
    return _sbcl_prelude() + "\n" + textwrap.dedent(
        f"""
        (load "{GRPC_FFI_PATH.as_posix()}")
        (load "{GRPC_TRANSPORT_PATH.as_posix()}")
        """
    )


def _run_sbcl_transport(script_body: str) -> str:
    script = _sbcl_transport_prelude() + "\n" + script_body + "\n"
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as handle:
        handle.write(script)
        script_path = Path(handle.name)
    try:
        completed = subprocess.run(
            ["sbcl", "--script", str(script_path)],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
    finally:
        try:
            script_path.unlink()
        except OSError:
            pass

    if completed.returncode != 0:
        raise RuntimeError(
            "SBCL transport script failed\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}\n"
            f"script:\n{script_body}"
        )
    return completed.stdout.strip()


def _run_cl_tls_probe(target: str, tls_root: Path, require_probe: bool = False) -> None:
    body = textwrap.dedent(
        f"""
        (ensure-grpc-available)
        (let ((channel (make-grpc-channel "{target}" :tls "{tls_root.as_posix()}")))
          (unwind-protect
              (unless (and channel (grpc-channel-alive-p channel))
                (error "TLS channel not alive"))
            (destroy-grpc-channel channel))
          (format t "OK~%"))
        """
    )
    try:
        _run_sbcl_transport(body)
    except RuntimeError as exc:
        if require_probe:
            raise
        print(f"[WARN] CL TLS probe skipped: {exc}")


def _bytes_to_hex(data: bytes) -> str:
    return data.hex().upper()


def _hex_to_bytes(hex_data: str) -> bytes:
    return bytes.fromhex("".join(hex_data.split()))


def _cl_encode_register_request(agent_id: str) -> bytes:
    body = textwrap.dedent(
        f"""
        (let* ((desc (list :agent-id "{agent_id}"
                           :name "CL Integration Agent"
                           :description "I59 integration harness"
                           :capabilities '("integration" "cl-sdk")
                           :communication-class 2
                           :registration-type 1
                           :max-concurrent-delegations 1))
               (encoded (encode-register-agent-request desc)))
          (loop for b across encoded do (format t "~2,'0X" b))
          (terpri))
        """
    )
    return _hex_to_bytes(_run_sbcl(body))


def _cl_assert_register_response(response_bytes: bytes) -> None:
    response_hex = _bytes_to_hex(response_bytes)
    body = textwrap.dedent(
        f"""
        (let* ((decoded (decode-register-agent-response (hex-to-octets "{response_hex}")))
               (accepted (getf decoded :accepted))
               (reason (getf decoded :reason)))
          (unless accepted
            (error "Register response not accepted: ~S" decoded))
          (unless (> (length reason) 0)
            (error "Register response reason missing: ~S" decoded))
          (format t "OK~%"))
        """
    )
    out = _run_sbcl(body)
    if "OK" not in out:
        raise RuntimeError(f"Unexpected CL register decode output: {out}")


def _cl_encode_send_request(producer_id: str, message_id: str, payload: bytes) -> bytes:
    payload_list = " ".join(str(item) for item in payload)
    body = textwrap.dedent(
        f"""
        (let* ((payload (make-array {len(payload)}
                                    :element-type '(unsigned-byte 8)
                                    :initial-contents '({payload_list})))
               (env (list :message-id "{message_id}"
                          :idempotency-token "idem-i59"
                          :producer-id "{producer_id}"
                          :correlation-id "corr-i59"
                          :sequence-number 1
                          :retry-count 0
                          :message-type 2
                          :content-type "application/octet-stream"
                          :content-length {len(payload)}
                          :repo-id "repo-i59"
                          :worktree-id "wt-i59"
                          :hlc-timestamp "HLC:1700001111000:0:i59"
                          :ttl-ms 20000
                          :payload payload
                          :state 1
                          :parent-correlation-id ""))
               (encoded (encode-send-message-request env)))
          (loop for b across encoded do (format t "~2,'0X" b))
          (terpri))
        """
    )
    return _hex_to_bytes(_run_sbcl(body))


def _cl_assert_send_response(response_bytes: bytes) -> None:
    response_hex = _bytes_to_hex(response_bytes)
    body = textwrap.dedent(
        f"""
        (let* ((decoded (decode-send-message-response (hex-to-octets "{response_hex}"))))
          (unless (getf decoded :accepted)
            (error "Send response not accepted: ~S" decoded))
          (format t "OK~%"))
        """
    )
    out = _run_sbcl(body)
    if "OK" not in out:
        raise RuntimeError(f"Unexpected CL send decode output: {out}")


def _cl_assert_stream_item(stream_item_bytes: bytes, expected_message_id: str, payload: bytes) -> None:
    item_hex = _bytes_to_hex(stream_item_bytes)
    payload_list = " ".join(str(item) for item in payload)
    body = textwrap.dedent(
        f"""
        (let* ((decoded (decode-stream-item (hex-to-octets "{item_hex}")))
               (payload (getf decoded :payload)))
          (unless decoded
            (error "Decoded stream item is NIL"))
          (unless (string= (getf decoded :message-id) "{expected_message_id}")
            (error "Unexpected stream message-id: ~S" decoded))
          (unless (equalp payload #({payload_list}))
            (error "Unexpected stream payload: ~S" payload))
          (format t "OK~%"))
        """
    )
    out = _run_sbcl(body)
    if "OK" not in out:
        raise RuntimeError(f"Unexpected CL stream decode output: {out}")


def _start_service(name: str, script_path: Path, env_var_name: str, port: int) -> ServiceProc:
    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PY_SDK_PATH}:{env.get('PYTHONPATH', '')}".rstrip(":")
    env[env_var_name] = str(port)
    env["PYTHONUNBUFFERED"] = "1"
    proc = subprocess.Popen(
        [sys.executable, str(script_path)],
        cwd=REPO_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return ServiceProc(name=name, proc=proc)


def _start_tls_service(
    name: str,
    module_path: Path,
    class_name: str,
    add_fn_name: str,
    port: int,
    cert_path: Path,
    key_path: Path,
) -> ServiceProc:
    service_script = textwrap.dedent(
        """
        import importlib.util
        import logging
        import signal
        import time
        from concurrent import futures

        import grpc


        def serve():
            logging.basicConfig(
                level=logging.INFO,
                format="%(asctime)s [%(levelname)s] %(message)s",
            )

            spec = importlib.util.spec_from_file_location("service_module", "MODULE_PATH")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)  # type: ignore

            server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
            service = getattr(module, "CLASS_NAME")()
            grpc_stub_module_name = next(
                (
                    key
                    for key in module.__dict__
                    if key.endswith("_pb2_grpc")
                ),
                None,
            )
            if grpc_stub_module_name is None:
                raise RuntimeError("Unable to resolve generated *_pb2_grpc module")
            else:
                candidate = module.__dict__[grpc_stub_module_name]

            add_fn = getattr(candidate, "ADD_FN_NAME")
            add_fn(service, server)

            with open("CERT_PATH", "rb") as cert_file, open("KEY_PATH", "rb") as key_file:
                server_creds = grpc.ssl_server_credentials(
                    ((key_file.read(), cert_file.read()),),
                    root_certificates=None,
                    require_client_auth=False,
                )
                listen_addr = f"0.0.0.0:PORT"
                bound_port = server.add_secure_port(listen_addr, server_creds)
                if bound_port == 0:
                    raise RuntimeError(f"Failed to bind TLS {listen_addr}")

            server.start()
            logging.info(f"SERVICE_NAME service started on {listen_addr}")

            def signal_handler(*_args, **_kwargs):
                server.stop(5)

            signal.signal(signal.SIGTERM, signal_handler)
            signal.signal(signal.SIGINT, signal_handler)

            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                server.stop(5)


        if __name__ == "__main__":
            serve()
        """
    )

    rendered = (
        service_script.replace("MODULE_PATH", str(module_path.as_posix()))
        .replace("CLASS_NAME", class_name)
        .replace("ADD_FN_NAME", add_fn_name)
        .replace("PORT", str(port))
        .replace("CERT_PATH", cert_path.as_posix())
        .replace("KEY_PATH", key_path.as_posix())
        .replace("SERVICE_NAME", name)
    )
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as handle:
        handle.write(rendered)
        script_path = Path(handle.name)

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{PY_SDK_PATH}:{env.get('PYTHONPATH', '')}".rstrip(":")
    proc = subprocess.Popen(
        [sys.executable, str(script_path)],
        cwd=REPO_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return ServiceProc(name=name, proc=proc)


def _wait_for_secure_channel_ready(address: str, cert_path: Path, timeout_seconds: float) -> None:
    credentials = grpc.ssl_channel_credentials(root_certificates=cert_path.read_bytes())
    channel = grpc.secure_channel(address, credentials)
    try:
        grpc.channel_ready_future(channel).result(timeout=timeout_seconds)
    finally:
        channel.close()


def _wait_for_channel_ready(address: str, timeout_seconds: float) -> None:
    channel = grpc.insecure_channel(address)
    try:
        grpc.channel_ready_future(channel).result(timeout=timeout_seconds)
    finally:
        channel.close()


def _stop_service(service: ServiceProc) -> str:
    proc = service.proc
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
    output = ""
    if proc.stdout is not None:
        output = proc.stdout.read()
    return output


def run_integration(timeout_seconds: float = 30.0) -> int:
    services: list[ServiceProc] = []
    service_logs: dict[str, str] = {}
    start_time = time.monotonic()

    registry_port = _find_free_port()
    router_port = _find_free_port()
    registry_addr = f"127.0.0.1:{registry_port}"
    router_addr = f"127.0.0.1:{router_port}"

    producer_agent = "cl-agent-i59"
    stream_agent = "i59-stream-recipient"
    message_id = "i59-msg-001"
    payload = b"\x0A\x14\x1E"
    readiness_timeout = max(5.0, min(15.0, timeout_seconds / 2.0))
    call_timeout = max(5.0, min(12.0, timeout_seconds / 3.0))
    stream_timeout = max(6.0, min(15.0, timeout_seconds / 2.0))

    try:
        services.append(
            _start_service("registry", REGISTRY_SERVICE_PATH, "REGISTRY_PORT", registry_port)
        )
        services.append(_start_service("router", ROUTER_SERVICE_PATH, "ROUTER_PORT", router_port))

        _wait_for_channel_ready(registry_addr, timeout_seconds=readiness_timeout)
        _wait_for_channel_ready(router_addr, timeout_seconds=readiness_timeout)

        # Register CL agent (CL-encoded request bytes -> live gRPC -> CL-decoded response bytes)
        register_request = _cl_encode_register_request(producer_agent)
        registry_channel = grpc.insecure_channel(registry_addr)
        try:
            register_rpc = registry_channel.unary_unary(
                "/sw4rm.registry.RegistryService/RegisterAgent",
                request_serializer=lambda data: data,
                response_deserializer=lambda data: data,
            )
            register_response = register_rpc(register_request, timeout=call_timeout)
        finally:
            registry_channel.close()
        _cl_assert_register_response(register_response)

        # Open a stream consumer so Router has an active recipient queue.
        router_channel = grpc.insecure_channel(router_addr)
        router_stub = router_pb2_grpc.RouterServiceStub(router_channel)
        stream_queue: queue.Queue[object] = queue.Queue(maxsize=1)

        def _stream_consumer() -> None:
            call = router_stub.StreamIncoming(
                router_pb2.StreamRequest(agent_id=stream_agent),
                timeout=stream_timeout,
            )
            try:
                item = next(call)
                stream_queue.put_nowait(item.SerializeToString())
            except StopIteration:
                stream_queue.put_nowait(RuntimeError("Stream closed before first item"))
            except Exception as exc:  # pragma: no cover - exceptional path
                stream_queue.put_nowait(exc)
            finally:
                call.cancel()

        consumer_thread = threading.Thread(target=_stream_consumer, daemon=True)
        consumer_thread.start()
        time.sleep(0.2)

        # Send router message using CL-encoded bytes.
        send_request = _cl_encode_send_request(
            producer_id=producer_agent,
            message_id=message_id,
            payload=payload,
        )
        send_rpc = router_channel.unary_unary(
            "/sw4rm.router.RouterService/SendMessage",
            request_serializer=lambda data: data,
            response_deserializer=lambda data: data,
        )
        send_response = send_rpc(send_request, timeout=call_timeout)
        _cl_assert_send_response(send_response)

        try:
            stream_item = stream_queue.get(timeout=stream_timeout)
        except queue.Empty as exc:
            raise RuntimeError("Timed out waiting for Router stream item") from exc

        consumer_thread.join(timeout=2.0)
        router_channel.close()

        if isinstance(stream_item, Exception):
            raise RuntimeError(f"Stream consumer failed: {stream_item}")

        assert isinstance(stream_item, bytes)
        decoded_item = router_pb2.StreamItem()
        decoded_item.ParseFromString(stream_item)
        if decoded_item.msg.message_id != message_id:
            raise RuntimeError(
                "Unexpected streamed message_id: "
                f"{decoded_item.msg.message_id} (expected {message_id})"
            )
        if decoded_item.msg.payload != payload:
            raise RuntimeError(
                "Unexpected streamed payload: "
                f"{decoded_item.msg.payload!r} (expected {payload!r})"
            )

        _cl_assert_stream_item(stream_item, expected_message_id=message_id, payload=payload)

        elapsed = time.monotonic() - start_time
        print(
            "[OK] CL reference gRPC integration passed "
            f"(registry={registry_addr}, router={router_addr}, elapsed={elapsed:.2f}s)"
        )
        return 0
    finally:
        for service in services:
            service_logs[service.name] = _stop_service(service)
        for name, logs in service_logs.items():
            if logs.strip():
                print(f"[{name}] logs:\n{logs.rstrip()}")


def run_tls_smoke(timeout_seconds: float = 30.0, require_cl_probe: bool = False) -> int:
    services: list[ServiceProc] = []
    service_logs: dict[str, str] = {}
    start_time = time.monotonic()

    with tempfile.TemporaryDirectory(prefix="sw4rm-tls-") as workdir:
        cert_path = Path(workdir) / "server.crt"
        key_path = Path(workdir) / "server.key"
        _generate_self_signed_cert(cert_path=cert_path, key_path=key_path)

        registry_port = _find_free_port()
        router_port = _find_free_port()
        registry_addr = f"localhost:{registry_port}"
        router_addr = f"localhost:{router_port}"
        readiness_timeout = max(5.0, min(15.0, timeout_seconds / 2.0))
        call_timeout = max(5.0, min(12.0, timeout_seconds / 3.0))

        try:
            services.append(
                _start_tls_service(
                    "registry",
                    REGISTRY_SERVICE_PATH,
                    "RegistryServiceImpl",
                    "add_RegistryServiceServicer_to_server",
                    registry_port,
                    cert_path,
                    key_path,
                )
            )
            services.append(
                _start_tls_service(
                    "router",
                    ROUTER_SERVICE_PATH,
                    "RouterServiceImpl",
                    "add_RouterServiceServicer_to_server",
                    router_port,
                    cert_path,
                    key_path,
                )
            )

            _wait_for_secure_channel_ready(registry_addr, cert_path, timeout_seconds=readiness_timeout)
            _wait_for_secure_channel_ready(router_addr, cert_path, timeout_seconds=readiness_timeout)

            root_cert = cert_path.read_bytes()

            # Register one producer on the secure Registry service.
            register_request = _cl_encode_register_request("cl-sdk-tls-agent")
            registry_channel = grpc.secure_channel(
                registry_addr,
                grpc.ssl_channel_credentials(root_certificates=root_cert),
            )
            try:
                register_rpc = registry_channel.unary_unary(
                    "/sw4rm.registry.RegistryService/RegisterAgent",
                    request_serializer=lambda data: data,
                    response_deserializer=lambda data: data,
                )
                register_response_bytes = register_rpc(register_request, timeout=call_timeout)
                register_response = registry_pb2.RegisterAgentResponse.FromString(register_response_bytes)
            finally:
                registry_channel.close()

            if not register_response.accepted:
                raise RuntimeError(f"TLS register failed: {register_response}")

            # Start one streaming consumer and send one message over Router.
            router_channel = grpc.secure_channel(
                router_addr,
                grpc.ssl_channel_credentials(root_certificates=root_cert),
            )
            consumer_thread: threading.Thread | None = None
            try:
                stream_queue: queue.Queue[Any] = queue.Queue(maxsize=1)

                def _stream_consumer() -> None:
                    call = router_pb2_grpc.RouterServiceStub(router_channel).StreamIncoming(
                        router_pb2.StreamRequest(agent_id="i60-tls-consumer"),
                        timeout=call_timeout,
                    )
                    try:
                        item = next(call)
                        stream_queue.put_nowait(item.SerializeToString())
                    except StopIteration:
                        stream_queue.put_nowait(RuntimeError("Stream closed before first item"))
                    except Exception as exc:  # pragma: no cover - exceptional path
                        stream_queue.put_nowait(exc)
                    finally:
                        call.cancel()

                consumer_thread = threading.Thread(target=_stream_consumer, daemon=True)
                consumer_thread.start()
                time.sleep(0.2)

                # Send one message via Router SendMessage over secure channel.
                send_request = _cl_encode_send_request(
                    producer_id="cl-sdk-tls-agent",
                    message_id="i60-tls-msg-001",
                    payload=b"OK",
                )
                send_rpc = router_channel.unary_unary(
                    "/sw4rm.router.RouterService/SendMessage",
                    request_serializer=lambda data: data,
                    response_deserializer=lambda data: data,
                )
                send_response_bytes = send_rpc(send_request, timeout=call_timeout)
                send_response = router_pb2.SendMessageResponse.FromString(send_response_bytes)
                if not send_response.accepted:
                    raise RuntimeError(f"TLS send failed: {send_response}")

                try:
                    stream_item = stream_queue.get(timeout=call_timeout)
                except queue.Empty as exc:
                    raise RuntimeError("TLS stream item not received") from exc

                if isinstance(stream_item, Exception):
                    raise RuntimeError(f"TLS stream consumer failed: {stream_item}")
                if not isinstance(stream_item, (bytes, bytearray)):
                    raise RuntimeError(f"Unexpected stream item type: {type(stream_item)}")

                _cl_assert_stream_item(
                    stream_item,
                    expected_message_id="i60-tls-msg-001",
                    payload=b"OK",
                )

                _run_cl_tls_probe(router_addr, cert_path, require_probe=require_cl_probe)

                elapsed = time.monotonic() - start_time
                print(
                    "[OK] CL TLS smoke test passed "
                    f"(registry={registry_addr}, router={router_addr}, elapsed={elapsed:.2f}s)"
                )
                return 0
            finally:
                if consumer_thread is not None:
                    consumer_thread.join(timeout=1.0)
                router_channel.close()
        finally:
            for service in services:
                service_logs[service.name] = _stop_service(service)
            for name, logs in service_logs.items():
                if logs.strip():
                    print(f"[{name}] logs:\n{logs.rstrip()}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run CL codec integration against reference Registry/Router gRPC services."
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=30.0,
        help="Overall timeout budget hint for readiness/calls (default: 30).",
    )
    parser.add_argument(
        "--tls-smoke",
        action="store_true",
        help="Run TLS self-signed certificate smoke test instead of I59 flow.",
    )
    parser.add_argument(
        "--require-cl-probe",
        action="store_true",
        help="Fail TLS smoke if the CL transport probe cannot establish TLS channel.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.tls_smoke:
        return run_tls_smoke(
            timeout_seconds=args.timeout_seconds,
            require_cl_probe=args.require_cl_probe,
        )

    try:
        return run_integration(timeout_seconds=args.timeout_seconds)
    except Exception as exc:
        print(f"[FAIL] CL reference gRPC integration failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
