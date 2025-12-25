from __future__ import annotations

from typing import Any


class WorktreeClient:
    """Client for managing agent worktree bindings and state transitions.

    The WorktreeClient provides access to the WorktreeService, which manages
    the binding of agents to Git worktrees for file system access. It implements
    a state machine with the following states:

    States:
        - UNBOUND: Agent has no worktree binding
        - BOUND_HOME: Agent is bound to its home worktree
        - SWITCH_PENDING: Agent has requested a worktree switch awaiting approval
        - BOUND_NON_HOME: Agent is temporarily bound to a non-home worktree
        - BIND_FAILED: Binding operation failed

    State Transitions:
        - UNBOUND -> BOUND_HOME: via bind()
        - BOUND_HOME -> SWITCH_PENDING: via request_switch()
        - SWITCH_PENDING -> BOUND_NON_HOME: via approve_switch()
        - SWITCH_PENDING -> BOUND_HOME: via reject_switch()
        - Any -> UNBOUND: via unbind()

    Example:
        >>> import grpc
        >>> channel = grpc.insecure_channel("localhost:50054")
        >>> client = WorktreeClient(channel)
        >>> client.bind("agent-1", "repo-main", "wt-feature")
    """

    def __init__(self, channel: Any) -> None:
        """Initialize the WorktreeClient.

        Args:
            channel: gRPC channel connected to the WorktreeService.
        """
        self._channel = channel
        try:
            from sw4rm.protos import worktree_pb2, worktree_pb2_grpc  # type: ignore
            self._pb2 = worktree_pb2
            self._stub = worktree_pb2_grpc.WorktreeServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def bind(self, agent_id: str, repo_id: str, worktree_id: str) -> Any:
        """Bind an agent to a worktree (UNBOUND -> BOUND_HOME).

        Establishes the agent's home worktree binding, providing it with
        file system access to the specified repository and worktree.

        Args:
            agent_id: Unique identifier of the agent to bind.
            repo_id: Repository identifier containing the worktree.
            worktree_id: Worktree identifier to bind to (becomes home worktree).

        Returns:
            BindResponse confirming the binding was successful.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., already bound, worktree not found).

        Example:
            >>> client.bind(
            ...     agent_id="dev-agent-1",
            ...     repo_id="repo-main",
            ...     worktree_id="wt-feature-auth"
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.BindRequest(agent_id=agent_id, repo_id=repo_id, worktree_id=worktree_id)
        return self._stub.Bind(req)

    def unbind(self, agent_id: str) -> Any:
        """Unbind an agent from its worktree (Any -> UNBOUND).

        Releases the agent's worktree binding, removing file system access.
        This can be called from any bound state.

        Args:
            agent_id: Unique identifier of the agent to unbind.

        Returns:
            UnbindResponse confirming the agent was unbound.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., agent not bound).

        Example:
            >>> client.unbind(agent_id="dev-agent-1")
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.UnbindRequest(agent_id=agent_id)
        return self._stub.Unbind(req)

    def status(self, agent_id: str) -> Any:
        """Get the current worktree binding status for an agent.

        Returns the agent's current worktree state, bound worktree ID,
        and any pending switch requests.

        Args:
            agent_id: Unique identifier of the agent to query.

        Returns:
            StatusResponse with current state, worktree_id, and switch status.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> status = client.status(agent_id="dev-agent-1")
            >>> print(f"State: {status.state}, Worktree: {status.worktree_id}")
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.StatusRequest(agent_id=agent_id)
        return self._stub.Status(req)

    def request_switch(self, agent_id: str, target_worktree_id: str, requires_hitl: bool = False) -> Any:
        """Request a worktree switch (BOUND_HOME -> SWITCH_PENDING).

        Initiates a request to switch the agent from its home worktree to
        a different worktree. If requires_hitl is True, human approval is
        required via approve_switch().

        Args:
            agent_id: Unique identifier of the agent requesting the switch.
            target_worktree_id: Worktree identifier to switch to.
            requires_hitl: Whether human-in-the-loop approval is required (default False).

        Returns:
            SwitchRequestResponse confirming the switch request was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., invalid state, worktree not found).

        Example:
            >>> client.request_switch(
            ...     agent_id="dev-agent-1",
            ...     target_worktree_id="wt-hotfix-security",
            ...     requires_hitl=True  # Needs approval for production worktree
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.SwitchRequest(agent_id=agent_id, target_worktree_id=target_worktree_id, requires_hitl=requires_hitl)
        return self._stub.RequestSwitch(req)

    def approve_switch(self, agent_id: str, target_worktree_id: str, ttl_ms: int) -> Any:
        """Approve a pending worktree switch (SWITCH_PENDING -> BOUND_NON_HOME).

        Approves a switch request that requires HITL approval, allowing the
        agent to bind to the target worktree with a time-to-live limit.

        Args:
            agent_id: Unique identifier of the agent whose switch is being approved.
            target_worktree_id: Worktree identifier being switched to (must match request).
            ttl_ms: Time-to-live in milliseconds for the non-home binding.

        Returns:
            SwitchApproveResponse confirming the switch was approved and executed.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., no pending switch, worktree mismatch).

        Example:
            >>> client.approve_switch(
            ...     agent_id="dev-agent-1",
            ...     target_worktree_id="wt-hotfix-security",
            ...     ttl_ms=300000  # 5 minutes
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.SwitchApprove(agent_id=agent_id, target_worktree_id=target_worktree_id, ttl_ms=ttl_ms)
        return self._stub.ApproveSwitch(req)

    def reject_switch(self, agent_id: str, reason: str = "") -> Any:
        """Reject a pending worktree switch (SWITCH_PENDING -> BOUND_HOME).

        Denies a switch request, returning the agent to its home worktree
        binding. This is typically used when HITL review determines the
        switch should not proceed.

        Args:
            agent_id: Unique identifier of the agent whose switch is being rejected.
            reason: Optional human-readable explanation for the rejection.

        Returns:
            SwitchRejectResponse confirming the switch was rejected.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails (e.g., no pending switch).

        Example:
            >>> client.reject_switch(
            ...     agent_id="dev-agent-1",
            ...     reason="Security policy violation: production access not approved"
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.SwitchReject(agent_id=agent_id, reason=reason)
        return self._stub.RejectSwitch(req)

