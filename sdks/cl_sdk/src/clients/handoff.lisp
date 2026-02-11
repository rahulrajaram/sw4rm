;;;; handoff.lisp - Handoff Service client for SW4RM
;;;;
;;;; Manages agent-to-agent handoff requests, responses, and status tracking.

(in-package :sw4rm)

;;;; Client Class

(defclass handoff-client (base-client)
  ()
  (:documentation "Client for managing agent handoff operations.

The handoff client provides methods for:
- Requesting handoffs to other agents
- Accepting/rejecting handoff requests
- Completing handoffs
- Querying pending handoffs

Handoffs enable graceful transfer of execution context from one agent
to another, typically when an agent needs specialized capabilities or
reaches the limits of its role.

Note: This is a local client (not gRPC-based) using in-memory storage.
For distributed deployments, this would interface with a HandoffService
via gRPC."))

;;;; RPC Methods

(defgeneric initiate-handoff (client request)
  (:documentation "Request a handoff to another agent.

Creates a new handoff request and returns a response with a unique
handoff ID. The handoff will be in PENDING status until the target
agent accepts or rejects it.

Args:
  client: The handoff-client instance.
  request: Handoff request plist with:
    :from-agent (string) - Agent initiating the handoff
    :to-agent (string) - Target agent to hand off to
    :reason (string) - Reason for the handoff
    :context (string or bytes) - Execution context to transfer
    :timeout (number, optional) - Timeout in seconds for acceptance (spec §17.6 MUST)
    :metadata (alist, optional) - Additional metadata

Returns:
  Handoff response plist with:
    :accepted (boolean) - Always T for pending status
    :handoff-id (string) - Unique handoff identifier
    :status (keyword) - :pending

Signals:
  RPC-ERROR: If handoff request fails.

Example:
  (initiate-handoff client
                    (list :from-agent \"agent-1\"
                          :to-agent \"specialist-agent\"
                          :reason \"Need specialized knowledge\"
                          :context \"{\\\"task\\\": \\\"analyze\\\", \\\"data\\\": ...}\"))"))

(defmethod initiate-handoff ((client handoff-client) request)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.InitiateHandoff
  ;; or use local in-memory storage
  (error 'rpc-error
         :message "InitiateHandoff not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))

(defgeneric accept-handoff (client handoff-id)
  (:documentation "Accept a pending handoff request.

Updates the handoff status to ACCEPTED and returns the updated response.

Args:
  client: The handoff-client instance.
  handoff-id: Unique identifier of the handoff to accept.

Returns:
  Updated handoff response plist with:
    :accepted (boolean) - T
    :status (keyword) - :accepted

Signals:
  RPC-ERROR: If handoff not found or not in PENDING status.

Example:
  (accept-handoff client \"handoff-123\")"))

(defmethod accept-handoff ((client handoff-client) handoff-id)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.AcceptHandoff
  (error 'rpc-error
         :message "AcceptHandoff not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))

(defgeneric reject-handoff (client handoff-id reason)
  (:documentation "Reject a pending handoff request.

Updates the handoff status to REJECTED with the provided reason.

Args:
  client: The handoff-client instance.
  handoff-id: Unique identifier of the handoff to reject.
  reason: Human-readable explanation of why the handoff was rejected.

Returns:
  Updated handoff response plist with:
    :accepted (boolean) - NIL
    :status (keyword) - :rejected
    :rejection-reason (string) - The rejection reason

Signals:
  RPC-ERROR: If handoff not found or not in PENDING status.

Example:
  (reject-handoff client \"handoff-123\" \"Agent unavailable\")"))

(defmethod reject-handoff ((client handoff-client) handoff-id reason)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.RejectHandoff
  (error 'rpc-error
         :message "RejectHandoff not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))

(defgeneric complete-handoff (client handoff-id)
  (:documentation "Mark a handoff as completed.

Updates the handoff status to COMPLETED after the receiving agent has
successfully taken over execution.

Args:
  client: The handoff-client instance.
  handoff-id: Unique identifier of the handoff to complete.

Returns:
  Updated handoff response plist with:
    :status (keyword) - :completed

Signals:
  RPC-ERROR: If handoff not found or not in ACCEPTED status.

Example:
  (complete-handoff client \"handoff-123\")"))

(defmethod complete-handoff ((client handoff-client) handoff-id)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.CompleteHandoff
  (error 'rpc-error
         :message "CompleteHandoff not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))

(defgeneric get-pending (client agent-id)
  (:documentation "Get all pending handoffs for a specific agent.

Returns all handoff requests that are waiting for the specified agent
to accept or reject them.

Args:
  client: The handoff-client instance.
  agent-id: ID of the agent to query for pending handoffs.

Returns:
  List of handoff request plists in PENDING status for this agent.

Signals:
  RPC-ERROR: If query fails.

Example:
  (get-pending client \"specialist-agent\")
  => ((:handoff-id \"handoff-123\"
       :from-agent \"agent-1\"
       :to-agent \"specialist-agent\"
       :reason \"Need specialized knowledge\"
       :status :pending)
      (:handoff-id \"handoff-124\" ...))"))

(defmethod get-pending ((client handoff-client) agent-id)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.GetPending
  (error 'rpc-error
         :message "GetPending not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))

(defgeneric get-handoff-status (client handoff-id)
  (:documentation "Get the current status of a handoff.

Args:
  client: The handoff-client instance.
  handoff-id: Unique identifier of the handoff.

Returns:
  Handoff response plist if found, NIL otherwise.

Signals:
  RPC-ERROR: If query fails.

Example:
  (get-handoff-status client \"handoff-123\")
  => (:handoff-id \"handoff-123\"
      :status :accepted
      :accepted-at \"2026-02-11T10:30:00Z\")"))

(defmethod get-handoff-status ((client handoff-client) handoff-id)
  (ensure-connected client)
  ;; Stub: In real implementation, this would call gRPC HandoffService.GetStatus
  (error 'rpc-error
         :message "GetHandoffStatus not implemented - requires gRPC or local storage integration"
         :code "UNIMPLEMENTED"))
