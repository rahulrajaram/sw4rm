import grpc  # type: ignore
from sw4rm.interceptors import CorrelationIdClientInterceptor, channel_with_interceptors


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
