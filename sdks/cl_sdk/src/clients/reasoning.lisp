;;;; reasoning.lisp - Reasoning Proxy client for SW4RM
;;;;
;;;; Provides AI-powered reasoning capabilities for parallelism checking,
;;;; debate evaluation, and text summarization.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass reasoning-client (base-client)
  ()
  (:documentation "Client for the SW4RM Reasoning Proxy Service.

The reasoning proxy provides AI-powered analysis capabilities:
- Parallelism checking: Determine if task scopes can run concurrently
- Debate evaluation: Compare and evaluate competing proposals
- Text summarization: Condense long conversations or documentation

The service uses LLM-based reasoning to provide intelligent analysis
beyond simple rule-based logic."))

;;;; RPC Methods

(defgeneric evaluate (client scope-a scope-b)
  (:documentation "Check if two scopes can be executed in parallel.

Uses AI reasoning to determine if two task scopes are independent
and can be safely executed concurrently. This is used by the scheduler
for automatic parallelism detection.

Args:
  client: The reasoning-client instance.
  scope-a: Description of the first task scope (string).
  scope-b: Description of the second task scope (string).

Returns:
  Parallelism check response plist with:
    :confidence-score (float) - Confidence that scopes are parallel (0.0-1.0)
    :notes (string) - Explanation of the reasoning
    :can-parallelize (boolean) - Whether parallel execution is safe

Signals:
  RPC-ERROR: If evaluation fails.

Example:
  (evaluate client
            \"Modify file src/parser.lisp\"
            \"Modify file test/parser-test.lisp\")
  => (:confidence-score 0.85
      :notes \"Different files, likely independent\"
      :can-parallelize t)"))

(defmethod evaluate ((client reasoning-client) scope-a scope-b)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ReasoningProxy.CheckParallelism
      (error 'rpc-error
             :message "Evaluate not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric parallel-evaluate (client negotiation-id proposal-a proposal-b
                                       &optional intensity)
  (:documentation "Evaluate competing proposals in a debate or negotiation.

Uses AI reasoning to compare and evaluate two competing proposals,
typically used in agent negotiation scenarios. Returns structured
analysis of strengths, weaknesses, and recommendations.

Args:
  client: The reasoning-client instance.
  negotiation-id: Unique identifier for the negotiation session.
  proposal-a: First proposal to evaluate (string).
  proposal-b: Second proposal to evaluate (string).
  intensity: Debate intensity level (\"low\", \"medium\", \"high\", default: \"low\").

Returns:
  Debate evaluation response plist with:
    :confidence-score (float) - Confidence in the evaluation (0.0-1.0)
    :notes (string) - Detailed evaluation and reasoning
    :preferred (keyword) - :proposal-a, :proposal-b, or :tie
    :strengths-a (list of strings) - Strengths of proposal A
    :strengths-b (list of strings) - Strengths of proposal B
    :synthesis (string, optional) - Suggested synthesis of both proposals

Signals:
  RPC-ERROR: If evaluation fails.

Example:
  (parallel-evaluate client \"neg-123\"
                     \"Use REST API with JSON\"
                     \"Use GraphQL API\"
                     \"medium\")"))

(defmethod parallel-evaluate ((client reasoning-client) negotiation-id
                              proposal-a proposal-b &optional (intensity "low"))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ReasoningProxy.EvaluateDebate
      (error 'rpc-error
             :message "ParallelEvaluate not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

(defgeneric summarize (client session-id segments &key max-tokens mode)
  (:documentation "Summarize text segments using AI.

Generates a concise summary of multiple text segments, useful for
condensing long conversations or documentation.

Args:
  client: The reasoning-client instance.
  session-id: Unique identifier for the summarization session.
  segments: List of text segment plists, each with:
    :kind (string) - Type of segment (e.g., \"user\", \"assistant\", \"system\")
    :content (string) - Text content of the segment
    :seq (integer) - Sequence number
    :at (string) - Timestamp or position marker
  max-tokens: Maximum number of tokens in the summary (default: 256).
  mode: Summarization mode (\"rolling\", \"full\", default: \"rolling\").

Returns:
  Summarization response plist with:
    :summary (string) - Generated summary text
    :tokens (integer) - Number of tokens used
    :cost-cents (float) - Cost of the operation in cents
    :model (string) - AI model used for summarization

Signals:
  RPC-ERROR: If summarization fails.

Example:
  (summarize client \"session-456\"
             (list (list :kind \"user\"
                         :content \"Can you explain monads?\"
                         :seq 1
                         :at \"2026-02-11T10:00:00Z\")
                   (list :kind \"assistant\"
                         :content \"Monads are...\"
                         :seq 2
                         :at \"2026-02-11T10:00:05Z\"))
             :max-tokens 128
             :mode \"full\")"))

(defmethod summarize ((client reasoning-client) session-id segments
                      &key (max-tokens 256) (mode "rolling"))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC ReasoningProxy.Summarize
      (error 'rpc-error
             :message "Summarize not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))
