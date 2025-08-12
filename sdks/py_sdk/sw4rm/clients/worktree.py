from __future__ import annotations

from typing import Any


class WorktreeClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import worktree_pb2, worktree_pb2_grpc  # type: ignore
            self._pb2 = worktree_pb2
            self._stub = worktree_pb2_grpc.WorktreeServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def bind(self, repo_id: str, worktree_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.BindRequest(repo_id=repo_id, worktree_id=worktree_id)
        return self._stub.Bind(req)

    def unbind(self, repo_id: str, worktree_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.UnbindRequest(repo_id=repo_id, worktree_id=worktree_id)
        return self._stub.Unbind(req)

    def status(self, repo_id: str, worktree_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.StatusRequest(repo_id=repo_id, worktree_id=worktree_id)
        return self._stub.Status(req)

