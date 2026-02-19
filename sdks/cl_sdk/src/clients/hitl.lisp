;;;; hitl.lisp - Human-in-the-Loop (HITL) Service client for SW4RM
;;;;
;;;; Handles escalation of decisions to human operators when agent confidence
;;;; is low, risks are high, or policy requires human approval.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass hitl-client (base-client)
  ()
  (:documentation "Client for the SW4RM Human-in-the-Loop (HITL) Service.

The HITL service provides:
- Decision escalation to human operators
- Invocation request management
- Human response capture and routing

Agents escalate to HITL when:
- Confidence scores are below threshold
- Risk levels exceed acceptable limits
- Policy explicitly requires human approval
- Ambiguous situations require human judgment

The service queues invocations for human review and routes responses
back to the requesting agents."))

;;;; RPC Methods

(defgeneric escalate (client invocation)
  (:documentation "Submit a HITL invocation for human decision.

Escalates a decision or action to a human operator for review and
approval. The invocation includes context, options, and metadata to
help the human make an informed decision.

Args:
  client: The hitl-client instance.
  invocation: HITL invocation plist with:
    :correlation-id (string) - Workflow/task correlation ID
    :reason-type (keyword) - Reason for escalation (:low-confidence,
                             :high-risk, :policy-required, :ambiguous)
    :context (string) - Detailed context for the human reviewer
    :options (list of plists) - Decision options, each with:
      :option-id (string) - Unique option identifier
      :label (string) - Human-readable label
      :description (string) - Detailed description
      :risk-level (keyword) - :low, :medium, :high
    :metadata (alist, optional) - Additional metadata
    :timeout-seconds (integer, optional) - Decision timeout

Returns:
  Decision response plist with:
    :decision-id (string) - Unique decision identifier
    :selected-option (string) - Option ID selected by human
    :notes (string, optional) - Human reviewer notes
    :decided-by (string) - Human operator identifier
    :decided-at (timestamp) - Decision timestamp

Signals:
  RPC-ERROR: If escalation fails or times out.

Example:
  (escalate client
            (list :correlation-id \"task-123\"
                  :reason-type :high-risk
                  :context \"About to delete production database table 'users'\"
                  :options (list (list :option-id \"proceed\"
                                       :label \"Proceed\"
                                       :description \"Delete the table\"
                                       :risk-level :high)
                                 (list :option-id \"cancel\"
                                       :label \"Cancel\"
                                       :description \"Abort the operation\"
                                       :risk-level :low))
                  :timeout-seconds 300))"))

(defmethod escalate ((client hitl-client) invocation)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-hitl-invocation invocation))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.hitl.HitlService/Decide"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-hitl-decision response-bytes)))))

(defgeneric respond (client decision-id selected-option &optional notes)
  (:documentation "Submit a human decision response.

Records a human operator's decision for a pending HITL invocation.
This is typically called by the HITL service UI or operator interface.

Args:
  client: The hitl-client instance.
  decision-id: Unique identifier of the pending decision.
  selected-option: Option ID selected by the human.
  notes: Optional notes or rationale from the human operator.

Returns:
  Response confirmation plist with :recorded boolean.

Signals:
  RPC-ERROR: If decision not found or response recording fails.

Example:
  (respond client \"decision-789\" \"cancel\"
           \"Too risky - need backup first\")"))

(defmethod respond ((client hitl-client) decision-id selected-option
                    &optional (notes ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC HitlService.Respond
      (error 'rpc-error
             :message "Respond not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric get-pending (client &optional operator-id)
  (:documentation "Get pending HITL invocations awaiting human decision.

Retrieves all invocations that are waiting for human review, optionally
filtered by the assigned operator.

Args:
  client: The hitl-client instance.
  operator-id: Optional operator ID to filter by assigned invocations.

Returns:
  List of pending invocation plists, each with:
    :decision-id (string) - Decision identifier
    :correlation-id (string) - Associated workflow/task
    :reason-type (keyword) - Escalation reason
    :context (string) - Context for review
    :options (list) - Available decision options
    :created-at (timestamp) - Invocation creation time
    :timeout-at (timestamp, optional) - Invocation timeout

Signals:
  RPC-ERROR: If query fails.

Example:
  ;; Get all pending invocations
  (get-pending client)

  ;; Get pending invocations for specific operator
  (get-pending client \"operator-alice\")"))

(defmethod get-pending ((client hitl-client) &optional operator-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC HitlService.GetPending
      (error 'rpc-error
             :message "GetPending not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric get-decision-status (client decision-id)
  (:documentation "Get the status of a HITL decision.

Retrieves the current state of a decision, including whether it has
been decided and the selected option.

Args:
  client: The hitl-client instance.
  decision-id: Unique identifier of the decision.

Returns:
  Decision status plist with:
    :decision-id (string) - Decision identifier
    :status (keyword) - :pending, :decided, or :timed-out
    :selected-option (string, optional) - Option ID if decided
    :notes (string, optional) - Human notes if decided
    :decided-at (timestamp, optional) - Decision timestamp

Signals:
  RPC-ERROR: If decision not found or query fails.

Example:
  (get-decision-status client \"decision-789\")
  => (:decision-id \"decision-789\"
      :status :decided
      :selected-option \"cancel\"
      :notes \"Too risky - need backup first\")"))

(defmethod get-decision-status ((client hitl-client) decision-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC HitlService.GetStatus
      (error 'rpc-error
             :message "GetDecisionStatus not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))
