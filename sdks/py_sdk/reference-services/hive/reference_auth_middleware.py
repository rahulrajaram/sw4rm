#!/usr/bin/env python3
"""Reference service authentication and authorization middleware."""

from __future__ import annotations

import base64
import hmac
import hashlib
import json
import logging
import os
import threading
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Set, Tuple

import grpc
from sw4rm import tracing


logger = logging.getLogger(__name__)


def _env_bool(value: Optional[str], default: bool = False) -> bool:
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _env_list(value: Optional[str]) -> List[str]:
    if not value:
        return []
    return [entry.strip() for entry in value.split(",") if entry.strip()]


def _env_float(value: Optional[str], default: float, minimum: float = 0.0) -> float:
    if value is None:
        return default
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        logger.warning("Invalid float env value %r; using default %.3f", value, default)
        return default
    if parsed <= minimum:
        return default
    return parsed


def _env_int(value: Optional[str], default: int, minimum: int = 0) -> int:
    if value is None:
        return default
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        logger.warning("Invalid integer env value %r; using default %d", value, default)
        return default
    if parsed <= minimum:
        return default
    return parsed


def _now_seconds() -> float:
    return __import__("time").time()


def _b64url_decode(value: str) -> bytes:
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def _b64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _method_name(method_path: str) -> str:
    return method_path.rsplit("/", 1)[-1] if method_path else ""


def _metadata_to_dict(metadata: Sequence[Any]) -> Dict[str, str]:
    normalized: Dict[str, str] = {}
    for item in metadata or []:
        key = str(getattr(item, "key", item[0] if isinstance(item, tuple) else "")).lower()
        value = str(getattr(item, "value", item[1] if isinstance(item, tuple) else ""))
        normalized[key] = value
    return normalized


@dataclass
class _RateLimitBucket:
    tokens: float
    last_refill: float


def issue_reference_token(
    agent_id: str,
    secret: str,
    ttl_seconds: int = 3600,
    now_fn: Any = None,
) -> str:
    """Create a compact HS256 JWT-like token with `sub`, `iat`, and `exp` claims."""
    if not agent_id:
        raise ValueError("agent_id required")
    if not secret:
        raise ValueError("secret required")
    if now_fn is None:
        now_fn = _now_seconds

    now = int(now_fn())
    header = {"alg": "HS256", "typ": "JWT"}
    claims = {"sub": agent_id, "iat": now, "exp": now + int(ttl_seconds)}
    header_blob = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    claim_blob = _b64url_encode(json.dumps(claims, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_blob}.{claim_blob}".encode("ascii")
    signature = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_blob}.{claim_blob}.{_b64url_encode(signature)}"


def decode_reference_token(token: str, secret: str, now_fn: Any = None) -> Mapping[str, Any]:
    """Verify and decode a compact HS256 token created by `issue_reference_token`."""
    if not token:
        raise ValueError("missing token")
    if not secret:
        raise ValueError("secret required")
    if now_fn is None:
        now_fn = _now_seconds

    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("invalid token format")

    raw_header, raw_payload, raw_signature = parts
    header_bytes = _b64url_decode(raw_header)
    payload_bytes = _b64url_decode(raw_payload)
    signature = _b64url_decode(raw_signature)

    header: Dict[str, Any] = json.loads(header_bytes.decode("utf-8"))
    if header.get("alg") != "HS256":
        raise ValueError("unsupported signing algorithm")

    signing_input = f"{raw_header}.{raw_payload}".encode("ascii")
    expected_signature = hmac.new(
        secret.encode("utf-8"),
        signing_input,
        hashlib.sha256,
    ).digest()
    if not hmac.compare_digest(signature, expected_signature):
        raise ValueError("invalid token signature")

    claims = json.loads(payload_bytes.decode("utf-8"))
    subject = claims.get("sub")
    if not subject or not isinstance(subject, str):
        raise ValueError("token missing subject")

    expires_at = claims.get("exp")
    if expires_at is not None:
        try:
            expiration_time = int(expires_at)
        except (TypeError, ValueError):
            raise ValueError("invalid token expiration")
        if int(now_fn()) > expiration_time:
            raise ValueError("token expired")

    return claims


def extract_subject_from_metadata(
    metadata: Sequence[Any],
    secret: str,
    now_fn: Any = None,
) -> Optional[str]:
    if now_fn is None:
        now_fn = _now_seconds
    raw = _metadata_to_dict(metadata)
    raw_token = raw.get("authorization") or raw.get("x-reference-token") or raw.get("x-api-token")
    if not raw_token:
        return None
    if isinstance(raw_token, str) and raw_token.lower().startswith("bearer "):
        raw_token = raw_token[7:].strip()
    if not isinstance(raw_token, str) or not raw_token:
        return None
    try:
        claims = decode_reference_token(raw_token, secret, now_fn=now_fn)
    except ValueError:
        return None
    return claims.get("sub") if isinstance(claims.get("sub"), str) else None


@dataclass
class ReferenceAuthPolicy:
    secret: str
    enabled: bool = False
    admin_agents: Set[str] = field(default_factory=set)
    method_permissions: Mapping[str, Set[str]] = field(default_factory=dict)
    agent_permissions: Mapping[str, Set[str]] = field(default_factory=dict)
    self_bound_methods: Set[str] = field(default_factory=set)

    @staticmethod
    def _default_admin_agents() -> Set[str]:
        return {"scheduler"}

    @staticmethod
    def _default_method_permissions() -> Dict[str, Set[str]]:
        return {
            "RegisterAgent": {"*"},
            "Heartbeat": {"*"},
            "DeregisterAgent": {"*"},
            "SendMessage": {"*"},
            "StreamIncoming": {"*"},
            "SubmitTask": {"*"},
            "RequestPreemption": {"scheduler"},
            "ShutdownAgent": {"scheduler"},
            "PollActivityBuffer": {"*"},
            "PurgeActivity": {"*"},
        }

    @staticmethod
    def _default_agent_permissions() -> Dict[str, Set[str]]:
        return {}

    @staticmethod
    def _default_self_bound_methods() -> Set[str]:
        return {
            "RegisterAgent",
            "Heartbeat",
            "DeregisterAgent",
            "SendMessage",
            "StreamIncoming",
            "SubmitTask",
            "PollActivityBuffer",
            "PurgeActivity",
        }

    @classmethod
    def _load_json_from_env(cls) -> Dict[str, Any]:
        policy_path = os.getenv("REFERENCE_AUTH_POLICY_PATH")
        if not policy_path:
            return {}
        try:
            with open(policy_path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
            if isinstance(payload, dict):
                return payload
            logger.warning("Ignoring non-dict policy payload from %s", policy_path)
        except FileNotFoundError:
            logger.warning("Auth policy file not found: %s", policy_path)
        except Exception:
            logger.exception("Failed to load reference auth policy from %s", policy_path)
        return {}

    @classmethod
    def _coerce_set(cls, value: Any) -> Set[str]:
        if value is None:
            return set()
        if isinstance(value, str):
            return {entry.strip() for entry in value.split(",") if entry.strip()}
        if isinstance(value, (list, tuple, set)):
            return {str(item).strip() for item in value if str(item).strip()}
        return set()

    @classmethod
    def from_environment(cls) -> "ReferenceAuthPolicy":
        enabled = _env_bool(os.getenv("REFERENCE_AUTH_ENABLED"), default=False)
        secret = os.getenv("REFERENCE_AUTH_JWT_SECRET", "")
        if not enabled:
            return cls(secret=secret, enabled=False)
        if not secret:
            raise ValueError("REFERENCE_AUTH_ENABLED is true but REFERENCE_AUTH_JWT_SECRET is not set")

        payload = cls._load_json_from_env()
        admin_agents = cls._coerce_set(_env_list(os.getenv("REFERENCE_AUTH_ADMIN_AGENTS")))
        if not admin_agents:
            admin_agents = cls._default_admin_agents().copy()
        admin_agents.update(cls._coerce_set(payload.get("admin_agents")))

        method_permissions: Dict[str, Set[str]] = {
            method: set(values)
            for method, values in cls._default_method_permissions().items()
        }
        for method_name, values in (payload.get("method_permissions") or {}).items():
            if isinstance(method_name, str) and isinstance(values, (list, tuple, set)):
                method_permissions[method_name] = set(values)

        agent_permissions: Dict[str, Set[str]] = {
            agent: set(values) for agent, values in cls._default_agent_permissions().items()
        }
        for agent, values in (payload.get("agent_permissions") or {}).items():
            if isinstance(agent, str) and isinstance(values, (list, tuple, set)):
                agent_permissions[agent] = set(values)

        configured_self_bound = payload.get("self_bound_methods")
        if configured_self_bound is not None:
            self_bound_methods = set(configured_self_bound)
        else:
            self_bound_methods = cls._default_self_bound_methods()

        return cls(
            secret=secret,
            enabled=True,
            admin_agents=admin_agents,
            method_permissions=method_permissions,
            agent_permissions=agent_permissions,
            self_bound_methods=self_bound_methods,
        )

    @classmethod
    def with_defaults(cls, secret: str) -> "ReferenceAuthPolicy":
        return cls(
            secret=secret,
            enabled=True,
            admin_agents=cls._default_admin_agents(),
            method_permissions=cls._default_method_permissions(),
            agent_permissions=cls._default_agent_permissions(),
            self_bound_methods=cls._default_self_bound_methods(),
        )

    @staticmethod
    def _request_actor_for_method(method_name: str, request: Any) -> Optional[str]:
        if request is None:
            return None
        if method_name == "RegisterAgent":
            return getattr(getattr(request, "agent", None), "agent_id", None)
        if method_name == "Heartbeat":
            return getattr(request, "agent_id", None)
        if method_name == "DeregisterAgent":
            return getattr(request, "agent_id", None)
        if method_name == "SendMessage":
            envelope = getattr(request, "msg", None)
            return getattr(envelope, "producer_id", None)
        if method_name in {"StreamIncoming", "SubmitTask", "PollActivityBuffer", "PurgeActivity", "RequestPreemption", "ShutdownAgent"}:
            return getattr(request, "agent_id", None)
        return None

    def authorize(self, method_name: str, actor: str, request: Any) -> bool:
        if not self.enabled:
            return True
        if not actor:
            return False

        allowed_methods = set(self.method_permissions.get(method_name, set()))
        allowed_methods.update(self.agent_permissions.get(actor, set()))

        # Admin agents are trusted to act on behalf of any agent and for service admin RPCs.
        if actor in self.admin_agents:
            return self._self_match_if_required(method_name, actor, request)

        if "*" in allowed_methods:
            return self._self_match_if_required(method_name, actor, request)

        if actor not in allowed_methods:
            return False

        return self._self_match_if_required(method_name, actor, request)

    def _requires_self_binding(self, method_name: str) -> bool:
        return method_name in self.self_bound_methods

    def _self_match_if_required(self, method_name: str, actor: str, request: Any) -> bool:
        if not self._requires_self_binding(method_name):
            return True
        request_actor = self._request_actor_for_method(method_name, request)
        return isinstance(request_actor, str) and request_actor == actor and actor in (self.admin_agents | {request_actor})

    def _method_permission_summary(self) -> Dict[str, List[str]]:
        return {
            method: sorted(methods)
            for method, methods in sorted(self.method_permissions.items())
        }


@dataclass
class ReferenceRateLimitPolicy:
    enabled: bool = False
    messages_per_second: float = 10.0
    burst_size: int = 10
    target_methods: Set[str] = field(default_factory=lambda: {"SendMessage"})
    now_fn: Any = field(default_factory=_now_seconds)
    _buckets: Dict[str, _RateLimitBucket] = field(default_factory=dict, init=False)
    _lock: threading.Lock = field(default_factory=threading.Lock, init=False)

    @classmethod
    def from_environment(cls) -> "ReferenceRateLimitPolicy":
        enabled = _env_bool(os.getenv("REFERENCE_RATE_LIMIT_ENABLED"), default=False)
        if not enabled:
            return cls(enabled=False)

        messages_per_second = _env_float(
            os.getenv("REFERENCE_RATE_LIMIT_MESSAGES_PER_SECOND"),
            default=10.0,
            minimum=0.0,
        )
        burst_size = _env_int(
            os.getenv("REFERENCE_RATE_LIMIT_BURST_SIZE"),
            default=max(1, int(messages_per_second)),
            minimum=1,
        )
        raw_methods = _env_list(os.getenv("REFERENCE_RATE_LIMIT_TARGET_METHODS"))
        methods = set(raw_methods) if raw_methods else {"SendMessage"}

        return cls(
            enabled=True,
            messages_per_second=messages_per_second,
            burst_size=max(1, burst_size),
            target_methods=methods,
            now_fn=_now_seconds,
        )

    @classmethod
    def with_defaults(
        cls,
        messages_per_second: float = 10.0,
        burst_size: int = 10,
        target_methods: Optional[Set[str]] = None,
        now_fn: Any = None,
    ) -> "ReferenceRateLimitPolicy":
        if now_fn is None:
            now_fn = _now_seconds
        return cls(
            enabled=True,
            messages_per_second=max(1e-3, float(messages_per_second)),
            burst_size=max(1, int(burst_size)),
            target_methods=target_methods or {"SendMessage"},
            now_fn=now_fn,
        )

    def _is_target_method(self, method_name: str) -> bool:
        return method_name in self.target_methods

    def _bucket_for(self, actor: str) -> _RateLimitBucket:
        now = float(self.now_fn())
        bucket = self._buckets.get(actor)
        if bucket is None:
            bucket = _RateLimitBucket(tokens=float(self.burst_size), last_refill=now)
            self._buckets[actor] = bucket
        return bucket

    def _resolve_actor(self, method_name: str, request: Any) -> Optional[str]:
        return ReferenceAuthPolicy._request_actor_for_method(method_name, request)

    def allow(self, method_name: str, actor: Optional[str]) -> tuple[bool, Optional[float]]:
        if not self.enabled or not actor or not self._is_target_method(method_name):
            return True, None
        if self.messages_per_second <= 0:
            return False, 0.0
        with self._lock:
            now = float(self.now_fn())
            bucket = self._bucket_for(actor)
            elapsed = max(0.0, now - bucket.last_refill)
            if elapsed > 0:
                bucket.tokens = min(
                    float(self.burst_size),
                    bucket.tokens + (elapsed * self.messages_per_second),
                )
                bucket.last_refill = now

            if bucket.tokens >= 1.0:
                bucket.tokens -= 1.0
                return True, None

            deficit = 1.0 - bucket.tokens
            retry_after = deficit / self.messages_per_second
            return False, retry_after


class ReferenceTracingInterceptor(grpc.ServerInterceptor):
    """gRPC interceptor that restores trace context for request-scoped logging + tracing."""

    def __init__(self, service_name: str = "reference-service") -> None:
        self._service_name = service_name

    def intercept_service(self, continuation, handler_call_details):
        handler = continuation(handler_call_details)
        if handler is None:
            return None

        method_name = _method_name(getattr(handler_call_details, "method", ""))
        if not method_name:
            return handler

        if handler.unary_unary is not None:
            return grpc.unary_unary_rpc_method_handler(
                self._wrap_unary_unary(method_name, handler.unary_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.unary_stream is not None:
            return grpc.unary_stream_rpc_method_handler(
                self._wrap_unary_stream(method_name, handler.unary_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_unary is not None:
            return grpc.stream_unary_rpc_method_handler(
                self._wrap_stream_unary(method_name, handler.stream_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_stream is not None:
            return grpc.stream_stream_rpc_method_handler(
                self._wrap_stream_stream(method_name, handler.stream_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        return handler

    def _resolve_trace_context(self, method_name: str, request: Any, context: grpc.ServicerContext) -> Optional[tracing.TraceContext]:
        _ = method_name
        metadata = getattr(context, "invocation_metadata", lambda: [])()
        parent = tracing.trace_context_from_metadata(metadata)
        if parent is not None:
            return tracing.create_child_span(parent, metadata={"operation": method_name, "service": self._service_name})

        parent = tracing.trace_context_from_envelope_metadata(getattr(request, "msg", request))
        if parent is None:
            return None
        return tracing.create_child_span(parent, metadata={"operation": method_name, "service": self._service_name})

    def _wrap_unary_unary(self, method_name: str, continuation_fn):
        def handler(request, context):
            trace = self._resolve_trace_context(method_name, request, context)
            if trace is None:
                return continuation_fn(request, context)
            with tracing.with_trace_context(trace):
                return continuation_fn(request, context)
        return handler

    def _wrap_unary_stream(self, method_name: str, continuation_fn):
        def handler(request, context):
            trace = self._resolve_trace_context(method_name, request, context)
            if trace is None:
                return continuation_fn(request, context)
            with tracing.with_trace_context(trace):
                return continuation_fn(request, context)
        return handler

    def _wrap_stream_unary(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            trace = self._resolve_trace_context(method_name, None, context)
            if trace is None:
                return continuation_fn(request_iterator, context)
            with tracing.with_trace_context(trace):
                return continuation_fn(request_iterator, context)
        return handler

    def _wrap_stream_stream(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            trace = self._resolve_trace_context(method_name, None, context)
            if trace is None:
                return continuation_fn(request_iterator, context)
            with tracing.with_trace_context(trace):
                return continuation_fn(request_iterator, context)
        return handler


class ReferenceRateLimitInterceptor(grpc.ServerInterceptor):
    """gRPC interceptor applying per-agent message quotas."""

    def __init__(self, policy: ReferenceRateLimitPolicy):
        self._policy = policy

    def intercept_service(self, continuation, handler_call_details):
        handler = continuation(handler_call_details)
        if handler is None:
            return None

        method_name = _method_name(getattr(handler_call_details, "method", ""))
        if not method_name:
            return handler

        if handler.unary_unary is not None:
            return grpc.unary_unary_rpc_method_handler(
                self._wrap_unary_unary(method_name, handler.unary_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.unary_stream is not None:
            return grpc.unary_stream_rpc_method_handler(
                self._wrap_unary_stream(method_name, handler.unary_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_unary is not None:
            return grpc.stream_unary_rpc_method_handler(
                self._wrap_stream_unary(method_name, handler.stream_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_stream is not None:
            return grpc.stream_stream_rpc_method_handler(
                self._wrap_stream_stream(method_name, handler.stream_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        return handler

    def _actor_id(self, method_name: str, request: Any, context: grpc.ServicerContext) -> Optional[str]:
        metadata = getattr(context, "invocation_metadata", lambda: [])()
        token_actor = extract_subject_from_metadata(metadata, os.getenv("REFERENCE_AUTH_JWT_SECRET", ""))
        if token_actor:
            return token_actor
        return self._policy._resolve_actor(method_name, request)

    def _enforce(self, method_name: str, request: Any, context: grpc.ServicerContext) -> None:
        actor = self._actor_id(method_name, request, context)
        allowed, retry_after = self._policy.allow(method_name, actor)
        if allowed:
            return
        detail = f"Per-agent message limit exceeded for {method_name}: {actor}"
        if retry_after is not None:
            detail = f"{detail} (retry_after={retry_after:.3f}s)"
        context.abort(grpc.StatusCode.RESOURCE_EXHAUSTED, detail)

    def _wrap_unary_unary(self, method_name: str, continuation_fn):
        def handler(request, context):
            self._enforce(method_name, request, context)
            return continuation_fn(request, context)
        return handler

    def _wrap_unary_stream(self, method_name: str, continuation_fn):
        def handler(request, context):
            self._enforce(method_name, request, context)
            return continuation_fn(request, context)
        return handler

    def _wrap_stream_unary(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            self._enforce(method_name, None, context)
            return continuation_fn(request_iterator, context)
        return handler

    def _wrap_stream_stream(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            self._enforce(method_name, None, context)
            return continuation_fn(request_iterator, context)
        return handler


class ReferenceAuthInterceptor(grpc.ServerInterceptor):
    """gRPC server interceptor applying JWT authz checks."""

    def __init__(self, policy: ReferenceAuthPolicy):
        self._policy = policy

    def intercept_service(self, continuation, handler_call_details):
        handler = continuation(handler_call_details)
        if handler is None:
            return None

        method_name = _method_name(getattr(handler_call_details, "method", ""))
        if not method_name:
            return handler

        if handler.unary_unary is not None:
            return grpc.unary_unary_rpc_method_handler(
                self._wrap_unary_unary(method_name, handler.unary_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.unary_stream is not None:
            return grpc.unary_stream_rpc_method_handler(
                self._wrap_unary_stream(method_name, handler.unary_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_unary is not None:
            return grpc.stream_unary_rpc_method_handler(
                self._wrap_stream_unary(method_name, handler.stream_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_stream is not None:
            return grpc.stream_stream_rpc_method_handler(
                self._wrap_stream_stream(method_name, handler.stream_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        return handler

    def _authorize(self, method_name: str, request: Any, context: grpc.ServicerContext) -> None:
        metadata = getattr(context, "invocation_metadata", lambda: [])()
        actor = extract_subject_from_metadata(metadata, self._policy.secret)
        if not actor:
            context.abort(grpc.StatusCode.UNAUTHENTICATED, "Missing or invalid auth token")
        if not self._policy.authorize(method_name, actor, request):
            context.abort(
                grpc.StatusCode.PERMISSION_DENIED,
                f"Actor {actor} is not authorized for {method_name}",
            )

    def _wrap_unary_unary(self, method_name: str, continuation_fn):
        def handler(request, context):
            self._authorize(method_name, request, context)
            return continuation_fn(request, context)
        return handler

    def _wrap_unary_stream(self, method_name: str, continuation_fn):
        def handler(request, context):
            self._authorize(method_name, request, context)
            return continuation_fn(request, context)
        return handler

    def _wrap_stream_unary(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            self._authorize(method_name, None, context)
            return continuation_fn(request_iterator, context)
        return handler

    def _wrap_stream_stream(self, method_name: str, continuation_fn):
        def handler(request_iterator, context):
            self._authorize(method_name, None, context)
            return continuation_fn(request_iterator, context)
        return handler


def build_auth_interceptors(service_name: Optional[str] = None) -> Sequence[grpc.ServerInterceptor]:
    interceptors: List[grpc.ServerInterceptor] = []

    try:
        from reference_metrics import build_reference_metrics_interceptor

        metrics_interceptor = build_reference_metrics_interceptor(
            service_name or "reference-service",
        )
        if metrics_interceptor is not None:
            interceptors.append(metrics_interceptor)
    except Exception as exc:  # pragma: no cover - defensive import fallback
        logger.debug("Reference metrics interceptor unavailable: %s", exc)

    try:
        from reference_logging import ReferenceLoggingInterceptor
    except Exception:  # pragma: no cover - defensive import fallback
        ReferenceLoggingInterceptor = None

    if ReferenceLoggingInterceptor is not None:
        interceptors.append(ReferenceLoggingInterceptor())

    interceptors.append(ReferenceTracingInterceptor(service_name=service_name or "reference-service"))

    auth_policy = ReferenceAuthPolicy.from_environment()
    if auth_policy.enabled:
        interceptors.append(ReferenceAuthInterceptor(policy=auth_policy))

    rate_limit_policy = ReferenceRateLimitPolicy.from_environment()
    if rate_limit_policy.enabled:
        interceptors.append(ReferenceRateLimitInterceptor(policy=rate_limit_policy))

    return interceptors
