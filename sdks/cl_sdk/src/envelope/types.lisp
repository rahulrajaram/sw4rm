;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; SW4RM Orchestrator - Cross-Swarm Envelope Types
;;;;
;;;; This module defines the core data structures for cross-swarm communication:
;;;;   - CROSS-SWARM-ENVELOPE: Message carrier with routing and lifecycle metadata
;;;;   - ROUTING-DECISION: Type for routing algorithm decisions
;;;;   - ROUTING-RESULT: Result of a routing computation
;;;;
;;;; The envelope carries messages across swarm boundaries with:
;;;;   - Three-ID model (message_id, correlation_id, idempotency_token) per spec §11.3
;;;;   - Routing information (source/target swarm, sender/recipient agent)
;;;;   - Payload carrying typed data
;;;;   - Path tracking (breadcrumb trail, hop count, deadline)
;;;;
;;;; Envelopes support:
;;;;   - Idempotent delivery via idempotency-token
;;;;   - Workflow correlation via correlation-id
;;;;   - Deadline enforcement (timeout protection)
;;;;   - Hop limiting (prevent infinite loops)
;;;;   - Priority-based routing
;;;;   - Message type classification
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0
;;;;
;;;; Spec References:
;;;;   - §11.3: Three-ID model (message_id, correlation_id, idempotency_token)
;;;;   - §5.2: Message correlation and tracing
;;;;   - §13: Buffers and back-pressure
;;;;   - §17+: Inter-agent negotiation patterns

(in-package :sw4rm-orchestrator.envelope)

;;;; ============================================================================
;;;; Type Definitions
;;;; ============================================================================

;;; ROUTING-DECISION: Type enumeration for routing decisions
;;;
;;; Represents the decision made by the router about how to handle an envelope:
;;;   :LOCAL      - Envelope is for this node (deliver locally)
;;;   :CHILD      - Forward to child node
;;;   :PARENT     - Forward to parent node
;;;   :BROADCAST  - Deliver to all children (discovery/notification)
;;;   :REJECT     - Cannot deliver (target not found, hop limit exceeded, etc.)
(deftype routing-decision ()
  "Type for routing algorithm decisions.

   Possible values:
     :LOCAL      - Target is this node
     :CHILD      - Forward to a child node
     :PARENT     - Forward to parent node
     :BROADCAST  - Deliver to all children
     :REJECT     - Cannot route (error condition)

   Example:
     (let ((decision (routing-result-decision result)))
       (ecase decision
         (:local (receive-envelope node envelope))
         (:child (route-child envelope))
         (:reject (handle-error result))))"
  '(member :local :child :parent :broadcast :reject))

;;;; ============================================================================
;;;; CROSS-SWARM-ENVELOPE Structure
;;;; ============================================================================

;;; CROSS-SWARM-ENVELOPE: Main message carrier for cross-swarm communication
;;;
;;; This structure carries messages across swarm boundaries with comprehensive
;;; metadata for routing, correlation, idempotency, and lifecycle management.
;;;
;;; Fields are organized by logical category:
;;;
;;;   IDs (Three-ID Model per spec §11.3):
;;;     - id: Unique message identifier (UUID, auto-generated, read-only)
;;;     - correlation-id: Workflow/conversation identifier
;;;     - idempotency-token: For exactly-once delivery semantics
;;;
;;;   Routing:
;;;     - source-swarm: Originating swarm ID
;;;     - target-swarm: Destination swarm ID
;;;     - sender: Agent originating the message
;;;     - recipient: Agent receiving the message
;;;
;;;   Payload:
;;;     - payload: Message data (any Lisp object)
;;;
;;;   Path tracking:
;;;     - path: Breadcrumb list of nodes visited
;;;     - hop-count: Current hop number (incremented at each node)
;;;     - max-hops: Maximum allowed hops (default 10)
;;;
;;;   Lifecycle:
;;;     - created-at: Timestamp (universal-time)
;;;     - deadline: Absolute deadline (universal-time or nil)
;;;     - priority: Message priority (:low, :normal, :high, :critical)
;;;     - message-type: Category (:request, :response, :event, :command)

(defstruct (cross-swarm-envelope (:conc-name envelope-))
  "Cross-swarm communication envelope with routing and lifecycle metadata.

   This structure implements the three-ID model from spec §11.3:
     - ID: Unique message identifier (auto-generated, read-only)
     - CORRELATION-ID: Tracks related messages across a workflow
     - IDEMPOTENCY-TOKEN: Enables exactly-once delivery semantics

   Fields:

   IDs (Three-ID Model):
     - ID (string): Unique message ID (UUID, auto-generated, read-only)
     - CORRELATION-ID (string or nil): Workflow identifier for related messages
     - IDEMPOTENCY-TOKEN (string or nil): Token for deduplication

   Routing:
     - SOURCE-SWARM (string or nil): Originating swarm
     - TARGET-SWARM (string or nil): Destination swarm
     - SENDER (string or nil): Agent sending the message
     - RECIPIENT (string or nil): Agent receiving the message

   Payload:
     - PAYLOAD (t): Message data (any Lisp object or JSON)

   Path Tracking:
     - PATH (list): Breadcrumb trail (e.g. (\"root\" \"cluster-a\" \"leaf-1\"))
     - HOP-COUNT (fixnum): Current hop number (starts at 0)
     - MAX-HOPS (fixnum): Maximum allowed hops (default 10)

   Lifecycle:
     - CREATED-AT (integer): Creation timestamp (universal-time)
     - DEADLINE (integer or nil): Absolute deadline (universal-time or nil)
     - PRIORITY (keyword): :low, :normal, :high, or :critical
     - MESSAGE-TYPE (keyword): :request, :response, :event, or :command

   Constraints:
     - ID is read-only (auto-generated UUID at construction)
     - MAX-HOPS defaults to 10
     - CREATED-AT defaults to current universal-time
     - PRIORITY defaults to :normal
     - MESSAGE-TYPE defaults to :request
     - PATH is an ordered list of node IDs (breadcrumb trail)
     - Deadlines are absolute (not relative)

   Example:
     (make-cross-swarm-envelope
       :correlation-id \"wf-123\"
       :idempotency-token \"agent-a:create:abc\"
       :source-swarm \"frontend\"
       :target-swarm \"backend\"
       :sender \"ui-agent\"
       :recipient \"api-agent\"
       :payload '(:event \"user-login\" :user-id 42)
       :priority :high
       :message-type :request
       :deadline (+ (get-universal-time) 300))  ; 5 minutes from now

   Spec References:
     - §11.3: Three-ID model (message_id, correlation_id, idempotency_token)
     - §5.2: Message correlation and tracing
     - §13: Buffers and back-pressure"

  (id (make-uuid) :type string :read-only t)
  (correlation-id nil :type (or null string))
  (idempotency-token nil :type (or null string))
  (source-swarm nil :type (or null string keyword))
  (target-swarm nil :type (or null string keyword))
  (sender nil :type (or null string))
  (recipient nil :type (or null string))
  (payload nil :type t)
  (path nil :type list)
  (hop-count 0 :type fixnum)
  (max-hops 10 :type fixnum)
  (created-at (get-universal-time) :type integer)
  (deadline nil :type (or null integer))
  (priority :normal :type (member :low :normal :high :critical))
  (message-type :request :type (member :request :response :event :command)))

;;;; ============================================================================
;;;; ROUTING-RESULT Structure
;;;; ============================================================================

;;; ROUTING-RESULT: Result of routing computation
;;;
;;; Returned by routing algorithms to communicate the decision and rationale.
;;;
;;; Fields:
;;;   - decision: The routing decision (:local, :child, :parent, :broadcast, :reject)
;;;   - target: Target node (swarm-tree object, swarm ID string, or nil)
;;;   - reason: Optional string explaining the decision (especially for :reject)
;;;   - latency-ms: Optional observed latency in milliseconds

(defstruct routing-result
  "Result of a routing computation.

   This structure is returned by routing algorithms to communicate the
   decision about how to handle an envelope and provide metadata.

   Fields:
     - DECISION (routing-decision): The routing decision
     - TARGET (swarm-tree or string or nil): Target node or swarm ID
     - REASON (string or nil): Explanation (especially for rejections)
     - LATENCY-MS (fixnum or nil): Observed latency in milliseconds

   Decision Semantics:
     - :LOCAL: Deliver to this node; target is (usually) this node
     - :CHILD: Forward to child; target is the child node or ID
     - :PARENT: Forward to parent; target is parent node or nil
     - :BROADCAST: Deliver to all children; target is nil
     - :REJECT: Cannot route; target is nil; reason explains why

   Example:
     (let ((result (compute-routing-decision node envelope)))
       (case (routing-result-decision result)
         (:local (receive-envelope node envelope))
         (:reject (format t \"Routing failed: ~A~%\" (routing-result-reason result)))))"

  (decision :reject :type routing-decision)
  (target nil :type (or null string))
  (reason nil :type (or null string))
  (latency-ms nil :type (or null fixnum)))

;;;; ============================================================================
;;;; UUID Generation
;;;; ============================================================================

(defun make-uuid ()
  "Generate a UUID string.

   Returns:
     A string representation of a UUID (36 characters, including hyphens).
     Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx (v4 random UUID)

   Notes:
     - Uses crypto-random-bytes for cryptographically strong randomness
     - Follows RFC 4122 version 4 (random UUID) specification
     - Returns uppercase hexadecimal with hyphens

   Example:
     (make-uuid)
     => \"550e8400-e29b-41d4-a716-446655440000\""
  ;; Simple UUID v4 generation using random numbers
  ;; This is a basic implementation that doesn't require external libraries
  (let ((bytes (make-array 16 :element-type '(unsigned-byte 8))))
    ;; Fill array with random bytes
    (dotimes (i 16)
      (setf (aref bytes i) (random 256)))

    ;; Set version to 4 (random) per RFC 4122
    (setf (aref bytes 6) (logior (logand (aref bytes 6) #x0f) #x40))
    ;; Set variant to RFC 4122 per RFC 4122
    (setf (aref bytes 8) (logior (logand (aref bytes 8) #x3f) #x80))

    ;; Convert to hex string with hyphens
    (with-output-to-string (out)
      (loop for i from 0 below 16
            do (progn
                 ;; Add hyphen at proper positions
                 (when (member i '(4 6 8 10))
                   (write-char #\- out))
                 ;; Write hex bytes
                 (format out "~2,'0x" (aref bytes i)))))))

;;;; ============================================================================
;;;; Validation Predicates
;;;; ============================================================================

(defun envelope-expired-p (envelope)
  "Check if envelope has passed its deadline.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to check

   Returns:
     T if the envelope has passed its deadline, NIL otherwise.
     Returns NIL if the envelope has no deadline.

   Example:
     (let ((env (make-cross-swarm-envelope
                  :deadline (- (get-universal-time) 10))))
       (envelope-expired-p env))
     => T"
  (and (envelope-deadline envelope)
       (>= (get-universal-time) (envelope-deadline envelope))))

(defun envelope-hop-limit-exceeded-p (envelope)
  "Check if envelope has exceeded its hop limit.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to check

   Returns:
     T if hop-count >= max-hops, NIL otherwise.

   Notes:
     This is a simple >= comparison. Routing algorithms typically check this
     before incrementing hop-count, so a check for >= is appropriate.

   Example:
     (let ((env (make-cross-swarm-envelope
                  :hop-count 10
                  :max-hops 10)))
       (envelope-hop-limit-exceeded-p env))
     => T"
  (>= (envelope-hop-count envelope)
      (envelope-max-hops envelope)))

(defun envelope-is-local-p (envelope target-swarm-id)
  "Check if envelope is destined for the given swarm.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to check
     target-swarm-id: String swarm ID to check against

   Returns:
     T if the envelope's target-swarm matches target-swarm-id, NIL otherwise.

   Notes:
     This is a simple predicate used in routing to determine if the envelope
     should be delivered locally or forwarded.

   Example:
     (let ((env (make-cross-swarm-envelope :target-swarm \"backend\")))
       (envelope-is-local-p env \"backend\"))
     => T"
  (and (envelope-target-swarm envelope)
       (string= (envelope-target-swarm envelope) target-swarm-id)))

;;;; ============================================================================
;;;; Path Tracking Utilities
;;;; ============================================================================

(defun envelope-add-to-path (envelope node-id)
  "Add a node ID to the envelope's path (breadcrumb trail).

   Args:
     envelope: CROSS-SWARM-ENVELOPE to modify
     node-id: String node ID to add

   Returns:
     The modified envelope.

   Notes:
     This is a destructive operation that modifies the envelope's path list.
     The path is typically updated at each hop to track the route taken.

   Example:
     (let ((env (make-cross-swarm-envelope :path '(\"root\"))))
       (envelope-add-to-path env \"cluster-a\")
       (envelope-path env))
     => (\"cluster-a\" \"root\")"
  (push node-id (envelope-path envelope))
  envelope)

(defun envelope-increment-hop-count (envelope)
  "Increment the envelope's hop count.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to modify

   Returns:
     The new hop count.

   Notes:
     This is a destructive operation. Typically called at each hop to track
     how many nodes the envelope has passed through.

   Example:
     (let ((env (make-cross-swarm-envelope :hop-count 0)))
       (envelope-increment-hop-count env)
       (envelope-hop-count env))
     => 1"
  (incf (envelope-hop-count envelope)))

(defun envelope-set-deadline (envelope timeout-seconds)
  "Set the envelope's deadline to a relative timeout.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to modify
     timeout-seconds: Number of seconds from now until deadline

   Returns:
     The absolute deadline timestamp (universal-time).

   Notes:
     This is a convenience function that computes an absolute deadline
     by adding the timeout to the current universal-time.
     This is a destructive operation.

   Example:
     (let ((env (make-cross-swarm-envelope)))
       (envelope-set-deadline env 300)  ; 5 minutes
       (envelope-deadline env))
     => 1704902400  ; Some future timestamp"
  (let ((deadline (+ (get-universal-time) timeout-seconds)))
    (setf (envelope-deadline envelope) deadline)))

(defun envelope-set_deadline (envelope timeout-seconds)
  "Compatibility wrapper for ENVELOPE-SET-DEADLINE."
  (envelope-set-deadline envelope timeout-seconds))

(defun envelope-remaining-ttl (envelope)
  "Compute remaining time-to-live for envelope in seconds.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to check

   Returns:
     Remaining seconds until deadline, or NIL if no deadline.
     Returns 0 if already expired (but negative values are never returned).

   Notes:
     Returns max(0, deadline - now) to avoid negative TTLs.
     Useful for deciding whether to attempt delivery.

   Example:
     (let ((env (make-cross-swarm-envelope
                  :deadline (+ (get-universal-time) 60))))
       (envelope-remaining-ttl env))
     => 60  ; approximately"
  (when (envelope-deadline envelope)
    (let ((remaining (- (envelope-deadline envelope) (get-universal-time))))
      (max 0 remaining))))

;;;; ============================================================================
;;;; Envelope Validation
;;;; ============================================================================

(defun validate-envelope (envelope)
  "Validate an envelope for correctness and consistency.

   Checks:
     - ID is present and non-empty
     - HOP-COUNT >= 0
     - MAX-HOPS > 0
     - HOP-COUNT <= MAX-HOPS
     - PRIORITY is a valid keyword
     - MESSAGE-TYPE is a valid keyword
     - CREATED-AT is a reasonable timestamp
     - DEADLINE (if present) is >= CREATED-AT
     - PATH is a proper list

   Args:
     envelope: CROSS-SWARM-ENVELOPE to validate

   Returns:
     T if all checks pass.

   Raises:
     ERROR if any validation check fails.

   Example:
     (validate-envelope (make-cross-swarm-envelope))
     => T

     (validate-envelope (make-cross-swarm-envelope :hop-count 15 :max-hops 10))
     => ERROR: HOP-COUNT (15) exceeds MAX-HOPS (10)"
  (flet ((check (condition message &rest args)
           (unless condition
             (apply #'error message args))))

    ;; ID checks
    (check (envelope-id envelope)
           "Envelope ID is missing")
    (check (> (length (envelope-id envelope)) 0)
           "Envelope ID is empty")

    ;; Hop count checks
    (check (>= (envelope-hop-count envelope) 0)
           "HOP-COUNT (~A) is negative" (envelope-hop-count envelope))
    (check (> (envelope-max-hops envelope) 0)
           "MAX-HOPS must be positive, got ~A" (envelope-max-hops envelope))
    (check (<= (envelope-hop-count envelope) (envelope-max-hops envelope))
           "HOP-COUNT (~A) exceeds MAX-HOPS (~A)"
           (envelope-hop-count envelope) (envelope-max-hops envelope))

    ;; Priority and type checks
    (check (member (envelope-priority envelope) '(:low :normal :high :critical))
           "Invalid PRIORITY: ~A" (envelope-priority envelope))
    (check (member (envelope-message-type envelope) '(:request :response :event :command))
           "Invalid MESSAGE-TYPE: ~A" (envelope-message-type envelope))

    ;; Timestamp checks
    (check (integerp (envelope-created-at envelope))
           "CREATED-AT must be an integer (universal-time)")
    (when (envelope-deadline envelope)
      (check (integerp (envelope-deadline envelope))
             "DEADLINE must be an integer (universal-time) or NIL")
      (check (>= (envelope-deadline envelope) (envelope-created-at envelope))
             "DEADLINE (~A) is before CREATED-AT (~A)"
             (envelope-deadline envelope) (envelope-created-at envelope)))

    ;; Path check
    (check (listp (envelope-path envelope))
           "PATH must be a list, got ~A" (type-of (envelope-path envelope)))

    t))

(defun envelope-valid-for-routing-p (envelope)
  "Quick predicate: is envelope valid for routing?

   This is a lighter-weight check than validate-envelope, checking only
   conditions that would prevent routing:
     - Has not exceeded hop limit
     - Has not expired
     - Has a target-swarm

   Args:
     envelope: CROSS-SWARM-ENVELOPE to check

   Returns:
     T if envelope can be routed, NIL otherwise.

   Example:
     (let ((env (make-cross-swarm-envelope :target-swarm \"backend\")))
       (envelope-valid-for-routing-p env))
     => T"
  (and
    (not (envelope-hop-limit-exceeded-p envelope))
    (not (envelope-expired-p envelope))
    (envelope-target-swarm envelope)))

;;;; ============================================================================
;;;; PRINT-OBJECT Method
;;;; ============================================================================

;;; Custom print-object for readable envelope representation
;;;
;;; Envelopes are printed in a compact but informative format:
;;;   #<ENVELOPE id: 550e8400... corr: wf-123 src: frontend -> dst: backend>
;;;
;;; This makes debugging and logging much easier than the default structure
;;; printer which would print all slots.

(defmethod print-object ((envelope cross-swarm-envelope) stream)
  "Print cross-swarm envelope in readable format.

   Format:
     #<ENVELOPE id: UUID... corr: ID src: SWARM dst: SWARM>

   Examples:
     #<ENVELOPE id: 550e8400-e29b-41d4-a7... corr: wf-123 src: frontend -> backend>
     #<ENVELOPE id: 123e4567-e89b-12d3-a4... (no correlation) src: nil -> nil>"
  (let ((id (envelope-id envelope))
        (corr (envelope-correlation-id envelope))
        (src (envelope-source-swarm envelope))
        (dst (envelope-target-swarm envelope)))
    (print-unreadable-object (envelope stream :type t :identity nil)
      (format stream "id: ~A~@[~A~] corr: ~@[~A~] src: ~@[~A~] -> dst: ~@[~A~]"
              ;; Print first 8 chars of UUID
              (subseq id 0 (min 8 (length id)))
              (if (> (length id) 8) "..." nil)
              corr
              src
              dst))))

;;;; ============================================================================
;;;; Copy Constructor (Deep Copy)
;;;; ============================================================================

(defun copy-cross-swarm-envelope (envelope)
  "Create a deep copy of an envelope.

   Args:
     envelope: CROSS-SWARM-ENVELOPE to copy

   Returns:
     A new CROSS-SWARM-ENVELOPE with all fields copied from the original.
     The new envelope has a new unique ID (not copied from original).
     The PATH list is deep-copied (not shared).

   Notes:
     The copy gets a fresh UUID; it is not identical to the original.
     The PATH list is copied but the path elements (strings) are shared
     (strings are immutable in Lisp).
     All other fields are copied by value.

   Example:
     (let* ((env (make-cross-swarm-envelope :correlation-id \"wf-123\"))
            (copy (copy-cross-swarm-envelope env)))
       (string= (envelope-id env) (envelope-id copy)))
     => NIL  ; Different IDs

     (let* ((env (make-cross-swarm-envelope :correlation-id \"wf-123\"))
            (copy (copy-cross-swarm-envelope env)))
       (string= (envelope-correlation-id env) (envelope-correlation-id copy)))
     => T  ; Same correlation ID"
  (make-cross-swarm-envelope
    :correlation-id (envelope-correlation-id envelope)
    :idempotency-token (envelope-idempotency-token envelope)
    :source-swarm (envelope-source-swarm envelope)
    :target-swarm (envelope-target-swarm envelope)
    :sender (envelope-sender envelope)
    :recipient (envelope-recipient envelope)
    :payload (envelope-payload envelope)
    :path (copy-list (envelope-path envelope))  ; Deep copy of path
    :hop-count (envelope-hop-count envelope)
    :max-hops (envelope-max-hops envelope)
    :created-at (envelope-created-at envelope)
    :deadline (envelope-deadline envelope)
    :priority (envelope-priority envelope)
    :message-type (envelope-message-type envelope)))

;;;; End of file
