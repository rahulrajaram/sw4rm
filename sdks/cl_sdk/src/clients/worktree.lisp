;;;; worktree.lisp - Worktree Service client for SW4RM
;;;;
;;;; Manages agent worktree bindings and state transitions for Git worktree
;;;; access control.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass worktree-client (base-client)
  ()
  (:documentation "Client for the SW4RM Worktree Service.

The worktree service manages bindings between agents and Git worktrees,
implementing a state machine for controlled file system access:

States:
  :unbound - Agent has no worktree binding
  :bound-home - Agent is bound to its home worktree
  :switch-pending - Agent has requested a worktree switch awaiting approval
  :bound-non-home - Agent is temporarily bound to a non-home worktree
  :bind-failed - Binding operation failed

State Transitions:
  :unbound -> :bound-home (via BIND)
  :bound-home -> :switch-pending (via REQUEST-SWITCH)
  :switch-pending -> :bound-non-home (via APPROVE-SWITCH)
  :switch-pending -> :bound-home (via REJECT-SWITCH)
  Any -> :unbound (via UNBIND)"))

;;;; RPC Methods

(defgeneric bind (client agent-id repo-id worktree-id)
  (:documentation "Bind an agent to a worktree (:unbound -> :bound-home).

Establishes the agent's home worktree binding, providing it with file
system access to the specified repository and worktree.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent to bind.
  repo-id: Repository identifier containing the worktree.
  worktree-id: Worktree identifier to bind to (becomes home worktree).

Returns:
  Bind response plist with :success boolean and :state.

Signals:
  RPC-ERROR: If binding fails (e.g., already bound, worktree not found).

Example:
  (bind client \"dev-agent-1\" \"repo-main\" \"wt-feature-auth\")"))

(defmethod bind ((client worktree-client) agent-id repo-id worktree-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-bind-request agent-id repo-id worktree-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/Bind"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-bind-response response-bytes)))))

(defgeneric unbind (client agent-id)
  (:documentation "Unbind an agent from its worktree (Any -> :unbound).

Releases the agent's worktree binding, removing file system access.
This can be called from any bound state.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent to unbind.

Returns:
  Unbind response plist with :success boolean.

Signals:
  RPC-ERROR: If unbinding fails (e.g., agent not bound).

Example:
  (unbind client \"dev-agent-1\")"))

(defmethod unbind ((client worktree-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-unbind-request agent-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/Unbind"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-unbind-response response-bytes)))))

(defgeneric switch-request (client agent-id target-worktree-id &key requires-hitl)
  (:documentation "Request a worktree switch (:bound-home -> :switch-pending).

Initiates a request to switch the agent from its home worktree to a
different worktree. If requires-hitl is true, human approval is required
via APPROVE-SWITCH.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent requesting the switch.
  target-worktree-id: Worktree identifier to switch to.
  requires-hitl: Whether human-in-the-loop approval is required (default: nil).

Returns:
  Switch request response plist with :pending boolean.

Signals:
  RPC-ERROR: If request fails (e.g., invalid state, worktree not found).

Example:
  (switch-request client \"dev-agent-1\" \"wt-hotfix-security\" :requires-hitl t)"))

(defmethod switch-request ((client worktree-client) agent-id target-worktree-id
                           &key (requires-hitl nil))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-switch-request agent-id target-worktree-id requires-hitl))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/RequestSwitch"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-worktree-status-response response-bytes)))))

(defgeneric approve-switch (client agent-id target-worktree-id ttl-ms)
  (:documentation "Approve a pending worktree switch (:switch-pending -> :bound-non-home).

Approves a switch request that requires HITL approval, allowing the
agent to bind to the target worktree with a time-to-live limit.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent whose switch is being approved.
  target-worktree-id: Worktree identifier being switched to (must match request).
  ttl-ms: Time-to-live in milliseconds for the non-home binding.

Returns:
  Approval response plist with :approved boolean.

Signals:
  RPC-ERROR: If approval fails (e.g., no pending switch, worktree mismatch).

Example:
  (approve-switch client \"dev-agent-1\" \"wt-hotfix-security\" 300000) ; 5 minutes"))

(defmethod approve-switch ((client worktree-client) agent-id target-worktree-id ttl-ms)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-switch-approve agent-id target-worktree-id ttl-ms))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/ApproveSwitch"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-worktree-status-response response-bytes)))))

(defgeneric reject-switch (client agent-id &optional reason)
  (:documentation "Reject a pending worktree switch (:switch-pending -> :bound-home).

Denies a switch request, returning the agent to its home worktree binding.
This is typically used when HITL review determines the switch should not proceed.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent whose switch is being rejected.
  reason: Optional human-readable explanation for the rejection.

Returns:
  Rejection response plist with :rejected boolean.

Signals:
  RPC-ERROR: If rejection fails (e.g., no pending switch).

Example:
  (reject-switch client \"dev-agent-1\" \"Security policy violation: production access not approved\")"))

(defmethod reject-switch ((client worktree-client) agent-id &optional (reason ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-switch-reject agent-id reason))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/RejectSwitch"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-worktree-status-response response-bytes)))))

(defgeneric status (client agent-id)
  (:documentation "Get the current worktree binding status for an agent.

Returns the agent's current worktree state, bound worktree ID, and any
pending switch requests.

Args:
  client: The worktree-client instance.
  agent-id: Unique identifier of the agent to query.

Returns:
  Status response plist with:
    :state (keyword) - Current state (:unbound, :bound-home, etc.)
    :worktree-id (string, optional) - Currently bound worktree
    :pending-switch (plist, optional) - Pending switch request details

Signals:
  RPC-ERROR: If status query fails.

Example:
  (status client \"dev-agent-1\")
  => (:state :bound-home
      :worktree-id \"wt-feature-auth\"
      :repo-id \"repo-main\")"))

(defmethod status ((client worktree-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-worktree-status-request agent-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.worktree.WorktreeService/Status"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-worktree-status-response response-bytes)))))
