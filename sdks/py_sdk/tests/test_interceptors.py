import grpc  # type: ignore
from unittest.mock import patch
from sw4rm import tracing
from sw4rm.interceptors import (
    CorrelationIdClientInterceptor,
    TracingClientInterceptor,
    channel_with_interceptors,
)


class DummyDetails(grpc.ClientCallDetails):  # type: ignore
    def __init__(self):
        self.method = '/x'
        self.timeout = 1
        self.metadata = (('foo','bar'),)
        self.credentials = None
        self.wait_for_ready = None
        self.compression = None


def test_correlation_id_interceptor_adds_metadata():
    ic = CorrelationIdClientInterceptor(correlation_id='cid-1', user_agent='ua')
    # simulate unary-unary path
    def cont(details, req):
        # Ensure metadata contains our headers
        md = dict(details.metadata)
        assert md.get('x-correlation-id') == 'cid-1'
        assert md.get('user-agent') == 'ua'
        return 'ok'
    assert ic.intercept_unary_unary(cont, DummyDetails(), b'') == 'ok'


def test_channel_with_interceptors_base_channel():
    # Without proper grpc interceptor subclasses, returns base channel
    ch = channel_with_interceptors('localhost:9')
    assert ch is not None


def test_tracing_client_interceptor_adds_trace_metadata():
    current_trace = tracing.TraceContext(trace_id="trace-id", span_id="span-id")
    details = DummyDetails()

    with patch("sw4rm.interceptors.tracing.get_current_trace", return_value=current_trace), patch(
        "sw4rm.interceptors.tracing.trace_context_to_metadata",
        return_value={"x-sw4rm-trace-id": "trace-id", "x-sw4rm-span-id": "span-id"},
    ):
        ic = TracingClientInterceptor()

        def cont(details_arg, _request):
            md = dict(details_arg.metadata)
            assert md["foo"] == "bar"
            assert md["x-sw4rm-trace-id"] == "trace-id"
            assert md["x-sw4rm-span-id"] == "span-id"
            return "ok"

        assert ic.intercept_unary_unary(cont, details, b"payload") == "ok"


def test_tracing_client_interceptor_without_current_trace():
    details = DummyDetails()
    with patch("sw4rm.interceptors.tracing.get_current_trace", return_value=None):
        ic = TracingClientInterceptor()

        def cont(details_arg, _request):
            return dict(details_arg.metadata)

        assert ic.intercept_unary_unary(cont, details, b"payload") == {
            "foo": "bar",
        }
