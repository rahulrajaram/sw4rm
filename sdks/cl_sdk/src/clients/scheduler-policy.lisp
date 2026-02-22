;;;; scheduler-policy.lisp - Scheduler Policy Service client for SW4RM
;;;;
;;;; Manages negotiation policies, policy profiles, and evaluation reports
;;;; for multi-agent negotiations coordinated by the scheduler.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass scheduler-policy-client (base-client)
  ()
  (:documentation "Client for the SW4RM Scheduler Policy Service.

The scheduler policy service provides:
- Global negotiation policy management
- Policy profiles (presets like LOW, MEDIUM, HIGH)
- Effective policy resolution for specific negotiations
- Evaluation report submission and tracking
- Human-in-the-loop (HITL) action recording

Policies control negotiation behavior including max rounds, score thresholds,
token budgets, and HITL intervention modes."))

;;;; RPC Methods

(defgeneric get-negotiation-policy (client)
  (:documentation "Get the current global negotiation policy.

Retrieves the active negotiation policy configuration that will be used
as the default for new negotiations.

Args:
  client: The scheduler-policy-client instance.

Returns:
  Negotiation policy plist with:
    :max-rounds (integer) - Maximum negotiation rounds
    :score-threshold (float) - Minimum score to accept (0.0-1.0)
    :token-budget-per-round (integer) - Max tokens per round
    :hitl-mode (string) - HITL intervention mode
    :timeout-seconds (integer, optional) - Negotiation timeout

Signals:
  RPC-ERROR: If policy retrieval fails.

Example:
  (get-negotiation-policy client)
  => (:max-rounds 10
      :score-threshold 0.8
      :token-budget-per-round 4000
      :hitl-mode \"PauseBetweenRounds\")"))

(defmethod get-negotiation-policy ((client scheduler-policy-client))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-get-negotiation-policy-request))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/GetNegotiationPolicy"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-get-negotiation-policy-response response-bytes)))))

(defgeneric set-negotiation-policy (client policy)
  (:documentation "Set the global negotiation policy.

Configures the default policy used for all negotiations unless overridden
by a specific profile. The policy defines constraints such as max rounds,
score thresholds, token budgets, and HITL modes.

Args:
  client: The scheduler-policy-client instance.
  policy: Negotiation policy plist with fields:
    :max-rounds (integer) - Maximum negotiation rounds
    :score-threshold (float) - Minimum score to accept (0.0-1.0)
    :token-budget-per-round (integer) - Max tokens per round
    :hitl-mode (string) - HITL intervention mode
    :timeout-seconds (integer, optional) - Negotiation timeout

Returns:
  Response plist with :success boolean.

Signals:
  RPC-ERROR: If policy update fails.

Example:
  (set-negotiation-policy client
                          (list :max-rounds 10
                                :score-threshold 0.8
                                :token-budget-per-round 4000
                                :hitl-mode \"PauseBetweenRounds\"))"))

(defmethod set-negotiation-policy ((client scheduler-policy-client) policy)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((policy-bytes (if (typep policy '(simple-array (unsigned-byte 8) (*)))
                               policy
                               (encode-negotiation-policy policy)))
             (request-bytes (encode-set-negotiation-policy-request policy-bytes))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/SetNegotiationPolicy"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-set-negotiation-policy-response response-bytes)))))

(defgeneric set-policy-profiles (client profiles)
  (:documentation "Set available policy profiles.

Policy profiles are named presets (e.g., LOW, MEDIUM, HIGH) that can be
selected by agents or workflows. Each profile contains a complete
policy configuration.

Args:
  client: The scheduler-policy-client instance.
  profiles: List of policy profile plists, each with:
    :profile-id (string) - Unique profile identifier
    :name (string) - Human-readable name
    :description (string) - Profile description
    :is-default (boolean) - Whether this is the default profile
    :policy (plist) - Negotiation policy configuration

Returns:
  Response plist with :count (number of profiles registered).

Signals:
  RPC-ERROR: If profile registration fails.

Example:
  (set-policy-profiles client
                       (list (list :profile-id \"low\"
                                   :name \"Low Intensity\"
                                   :is-default t
                                   :policy '(:max-rounds 3 :score-threshold 0.6))
                             (list :profile-id \"high\"
                                   :name \"High Intensity\"
                                   :is-default nil
                                   :policy '(:max-rounds 15 :score-threshold 0.9))))"))

(defmethod set-policy-profiles ((client scheduler-policy-client) profiles)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (if (typep profiles '(simple-array (unsigned-byte 8) (*)))
                                profiles
                                (encode-set-policy-profiles-request profiles)))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/SetPolicyProfiles"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-set-policy-profiles-response response-bytes)))))

(defgeneric list-policy-profiles (client)
  (:documentation "List all available policy profiles.

Returns all registered policy profiles that can be selected for negotiations.

Args:
  client: The scheduler-policy-client instance.

Returns:
  List of policy profile plists.

Signals:
  RPC-ERROR: If listing fails.

Example:
  (list-policy-profiles client)
  => ((:profile-id \"low\" :name \"Low Intensity\" :is-default t)
      (:profile-id \"medium\" :name \"Medium Intensity\" :is-default nil)
      (:profile-id \"high\" :name \"High Intensity\" :is-default nil))"))

(defmethod list-policy-profiles ((client scheduler-policy-client))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (make-array 0 :element-type '(unsigned-byte 8)))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/ListPolicyProfiles"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-list-policy-profiles-response response-bytes)))))

(defgeneric get-effective-policy (client negotiation-id)
  (:documentation "Get the effective policy for a specific negotiation.

Retrieves the resolved policy that is active for the given negotiation,
including any profile selections and agent preference overrides.

Args:
  client: The scheduler-policy-client instance.
  negotiation-id: Unique identifier of the negotiation.

Returns:
  Effective policy plist with resolved configuration.

Signals:
  RPC-ERROR: If policy retrieval fails or negotiation not found.

Example:
  (get-effective-policy client \"neg-123\")
  => (:max-rounds 10
      :score-threshold 0.8
      :profile-id \"medium\"
      :overrides (:token-budget-per-round 5000))"))

(defmethod get-effective-policy ((client scheduler-policy-client) negotiation-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-get-effective-policy-request negotiation-id))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/GetEffectivePolicy"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-get-effective-policy-response response-bytes)))))

(defgeneric submit-evaluation (client negotiation-id report)
  (:documentation "Submit an evaluation report for a negotiation round.

Agents submit evaluation reports after each round to record scores,
deltas from previous versions, and qualitative feedback. The scheduler
uses these reports to determine if the negotiation should continue or
terminate.

Args:
  client: The scheduler-policy-client instance.
  negotiation-id: Unique identifier of the negotiation.
  report: Evaluation report plist with:
    :round-number (integer) - Current round number
    :scores (alist) - Score dimensions and values
    :delta (float, optional) - Improvement from previous round
    :summary (string) - Qualitative feedback
    :agent-id (string) - Evaluating agent ID

Returns:
  Response plist with :accepted boolean.

Signals:
  RPC-ERROR: If submission fails.

Example:
  (submit-evaluation client \"neg-123\"
                     (list :round-number 2
                           :scores '((:quality . 8.5) (:security . 9.0))
                           :delta 0.3
                           :summary \"Good progress on both fronts\"
                           :agent-id \"critic-1\"))"))

(defmethod submit-evaluation ((client scheduler-policy-client) negotiation-id report)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((report-bytes (if (typep report '(simple-array (unsigned-byte 8) (*)))
                               report
                               (encode-policy-evaluation-report report))
                 )
             (request-bytes (encode-submit-evaluation-request negotiation-id report-bytes))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/SubmitEvaluation"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-submit-evaluation-response response-bytes)))))

(defgeneric hitl-action (client negotiation-id action &optional rationale)
  (:documentation "Record a human-in-the-loop action for a negotiation.

When HITL mode is enabled in the policy, this method is used to record
human decisions (approve, reject, continue, escalate) during the
negotiation process.

Args:
  client: The scheduler-policy-client instance.
  negotiation-id: Unique identifier of the negotiation.
  action: HITL action (e.g., \"approve\", \"reject\", \"continue\", \"escalate\").
  rationale: Optional human-readable explanation for the action.

Returns:
  Response plist with :recorded boolean.

Signals:
  RPC-ERROR: If action recording fails.

Example:
  (hitl-action client \"neg-123\" \"approve\"
               \"Manual review confirms security is adequate\")"))

(defmethod hitl-action ((client scheduler-policy-client) negotiation-id action
                        &optional (rationale ""))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-hitl-action-request negotiation-id action rationale))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.scheduler.SchedulerPolicyService/HitlAction"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-hitl-action-response response-bytes)))))
