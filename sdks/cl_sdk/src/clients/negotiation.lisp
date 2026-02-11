;;;; negotiation.lisp - Negotiation Service client for SW4RM
;;;;
;;;; Manages multi-agent negotiation sessions with proposals, counter-proposals,
;;;; evaluations, and decisions.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass negotiation-client (base-client)
  ()
  (:documentation "Client for the SW4RM Negotiation Service.

The negotiation service enables collaborative decision-making between
multiple agents through a structured workflow:

Workflow:
  1. OPEN - Initiate a negotiation session with participants
  2. PROPOSE - First agent submits initial proposal
  3. COUNTER - Other agents submit counter-proposals (multiple rounds)
  4. EVALUATE - Agents evaluate current proposals with confidence scores
  5. DECIDE - Coordinator makes final decision to close negotiation
  6. ABORT - Cancel negotiation if needed

The service supports configurable debate intensity levels (LOWEST to
HIGHEST) and timeouts to control the negotiation process."))

;;;; RPC Methods

(defgeneric create-session (client negotiation-id correlation-id topic participants
                                   &key intensity debate-timeout-seconds)
  (:documentation "Open a new negotiation session.

Initiates a multi-agent negotiation with specified participants and
parameters. The negotiation remains open until a decision is made or
it is aborted.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier for this negotiation session.
  correlation-id: Identifier linking this negotiation to a larger workflow.
  topic: Human-readable description of what is being negotiated.
  participants: List of agent IDs that will participate.
  intensity: Debate intensity level (0=LOWEST to 4=HIGHEST, default 0).
  debate-timeout-seconds: Optional timeout in seconds for the entire negotiation.

Returns:
  Open response plist with :success boolean.

Signals:
  RPC-ERROR: If session creation fails.

Example:
  (create-session client \"neg-design-123\" \"workflow-456\"
                  \"API Design Review\"
                  '(\"architect-1\" \"security-reviewer\" \"api-reviewer\")
                  :intensity 2
                  :debate-timeout-seconds 600)"))

(defmethod create-session ((client negotiation-client) negotiation-id correlation-id
                           topic participants &key (intensity 0) debate-timeout-seconds)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Open
      (error 'rpc-error
             :message "CreateSession not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric submit-proposal (client negotiation-id from-agent content-type payload)
  (:documentation "Submit an initial proposal to a negotiation.

The first agent to submit a proposal defines the starting point for
the negotiation. Other agents will respond with counter-proposals or
evaluations.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.
  from-agent: Agent ID submitting the proposal.
  content-type: MIME type or content type of the payload.
  payload: Binary payload containing the proposal (e.g., JSON, protobuf).

Returns:
  Proposal response plist with :accepted boolean.

Signals:
  RPC-ERROR: If proposal submission fails.

Example:
  (submit-proposal client \"neg-123\" \"architect-1\" \"application/json\"
                   (babel:string-to-octets
                    \"{\\\"endpoint\\\": \\\"/api/v2/users\\\", \\\"method\\\": \\\"POST\\\"}\"))"))

(defmethod submit-proposal ((client negotiation-client) negotiation-id from-agent
                            content-type payload)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Propose
      (error 'rpc-error
             :message "SubmitProposal not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric vote (client negotiation-id from-agent confidence-score &optional notes)
  (:documentation "Submit an evaluation of the current proposal.

Agents evaluate proposals to indicate their level of agreement or
satisfaction. The confidence score (0.0-1.0) indicates how confident
the agent is in their evaluation.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.
  from-agent: Agent ID submitting the evaluation.
  confidence-score: Confidence level from 0.0 (uncertain) to 1.0 (certain).
  notes: Optional qualitative feedback or explanation.

Returns:
  Evaluation response plist with :recorded boolean.

Signals:
  RPC-ERROR: If evaluation submission fails.

Example:
  (vote client \"neg-123\" \"reviewer-1\" 0.85
        \"Looks good but needs more error handling\")"))

(defmethod vote ((client negotiation-client) negotiation-id from-agent
                 confidence-score &optional (notes ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Evaluate
      (error 'rpc-error
             :message "Vote not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric get-session (client negotiation-id)
  (:documentation "Retrieve the current state of a negotiation session.

Fetches the negotiation's status, participants, proposals, and evaluations.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.

Returns:
  Session state plist with:
    :negotiation-id (string) - Session identifier
    :status (keyword) - :open, :decided, or :aborted
    :participants (list) - List of participant agent IDs
    :proposals (list) - List of submitted proposals
    :evaluations (list) - List of submitted evaluations
    :decision (plist, optional) - Final decision if decided

Signals:
  RPC-ERROR: If session not found or retrieval fails.

Example:
  (get-session client \"neg-123\")
  => (:negotiation-id \"neg-123\"
      :status :open
      :participants (\"agent-1\" \"agent-2\")
      :proposals (...)
      :evaluations (...))"))

(defmethod get-session ((client negotiation-client) negotiation-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.GetSession
      (error 'rpc-error
             :message "GetSession not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

;;;; Helper Methods (from Python SDK)

(defgeneric counter-proposal (client negotiation-id from-agent content-type payload)
  (:documentation "Submit a counter-proposal to a negotiation.

Agents use counter-proposals to suggest modifications to the current
proposal. Multiple rounds of counter-proposals can occur until consensus
is reached or the negotiation is decided/aborted.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.
  from-agent: Agent ID submitting the counter-proposal.
  content-type: MIME type or content type of the payload.
  payload: Binary payload containing the counter-proposal.

Returns:
  Counter-proposal response plist with :accepted boolean.

Signals:
  RPC-ERROR: If counter-proposal submission fails.

Example:
  (counter-proposal client \"neg-123\" \"security-agent\" \"application/json\"
                    (babel:string-to-octets
                     \"{\\\"endpoint\\\": \\\"/api/v2/users\\\", \\\"method\\\": \\\"POST\\\", \\\"auth\\\": \\\"required\\\"}\"))"))

(defmethod counter-proposal ((client negotiation-client) negotiation-id from-agent
                             content-type payload)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Counter
      (error 'rpc-error
             :message "CounterProposal not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric decide (client negotiation-id decided-by content-type result)
  (:documentation "Make a final decision to conclude the negotiation.

Typically called by a coordinator or lead agent to finalize the
negotiation with the agreed-upon outcome. This closes the negotiation.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.
  decided-by: Agent ID making the final decision.
  content-type: MIME type or content type of the result.
  result: Binary payload containing the final decision/agreement.

Returns:
  Decision response plist with :recorded boolean.

Signals:
  RPC-ERROR: If decision recording fails.

Example:
  (decide client \"neg-123\" \"coordinator-1\" \"application/json\"
          (babel:string-to-octets
           \"{\\\"endpoint\\\": \\\"/api/v2/users\\\", \\\"method\\\": \\\"POST\\\", \\\"approved\\\": true}\"))"))

(defmethod decide ((client negotiation-client) negotiation-id decided-by
                   content-type result)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Decide
      (error 'rpc-error
             :message "Decide not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric abort-negotiation (client negotiation-id &optional reason)
  (:documentation "Abort an ongoing negotiation.

Terminates the negotiation without reaching a decision. This can be
called when the negotiation is no longer relevant or has reached an
impasse.

Args:
  client: The negotiation-client instance.
  negotiation-id: Unique identifier of the negotiation session.
  reason: Optional explanation for why the negotiation is being aborted.

Returns:
  Abort response plist with :aborted boolean.

Signals:
  RPC-ERROR: If abort fails.

Example:
  (abort-negotiation client \"neg-123\"
                     \"Requirements changed, no longer applicable\")"))

(defmethod abort-negotiation ((client negotiation-client) negotiation-id
                              &optional (reason ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC NegotiationService.Abort
      (error 'rpc-error
             :message "AbortNegotiation not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))
