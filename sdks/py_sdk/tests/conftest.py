import os
import sys


def pytest_sessionstart(session):
    # Ensure generated *_pb2 modules (which use absolute imports like 'import common_pb2') are importable
    here = os.path.dirname(__file__)
    protos_dir = os.path.normpath(os.path.join(here, '..', 'sw4rm', 'protos'))
    if protos_dir not in sys.path:
        sys.path.insert(0, protos_dir)

