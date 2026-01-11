;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; errors/conditions.lisp
;;;;
;;;; Condition Hierarchy for Distributed Error Handling
;;;;
;;;; This module defines the Common Lisp condition system for sophisticated
;;;; distributed error handling in the SW4RM orchestrator.
;;;;
;;;; The condition system is the most powerful error handling mechanism in any
;;;; programming language because it separates:
;;;;   - Error DETECTION (signaling a condition)
;;;;   - Error HANDLING (handler-bind, invoke-restart)
;;;;
;;;; This allows high-level code to handle errors without requiring try-catch
;;;; in every layer, and enables restarts to alter control flow dynamically.
;;;;
;;;; Condition Hierarchy:
;;;;   SW4RM-ERROR (base)
;;;;   ├── SWARM-UNREACHABLE
;;;;   ├── SWARM-DISCONNECTED
;;;;   ├── ROUTING-ERROR
;;;;   │   ├── HOP-LIMIT-EXCEEDED
;;;;   │   └── DEADLINE-EXCEEDED
;;;;   ├── ENVELOPE-ERROR
;;;;   ├── IDEMPOTENT-DELIVERY-ERROR
;;;;   ├── DELIVERY-FAILED
;;;;   └── COORDINATION-ERROR
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.errors)

;;;; ============================================================================
;;;; Base Condition: SW4RM-ERROR
;;;; ============================================================================

(define-condition sw4rm-error (error)
  ((message
    :initarg :message
    :reader sw4rm-error-message
    :type string
    :documentation "Human-readable error message.")

   (timestamp
    :reader error-timestamp
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when error was signaled.

    Timestamp in Common Lisp universal time format (seconds since 1900-01-01).
    Automatically recorded at error creation time.")

   (context
    :initarg :context
    :reader error-context
    :initform nil
    :type list
    :documentation "Plist of contextual information about the error.

    Example: (:envelope-id \"msg-123\" :source-swarm \"leaf-a\" :attempt 3)

    This allows handlers to make informed decisions based on the context
    without needing to examine the full error instance."))

  (:report (lambda (condition stream)
             (format stream "SW4RM error: ~A"
                     (sw4rm-error-message condition))))

  (:documentation "Base condition class for all SW4RM orchestration errors.

  All error conditions in the SW4RM system inherit from SW4RM-ERROR.
  This enables high-level handlers to catch any SW4RM error with a single
  handler-bind clause.

  Slots:
    message - Description of the error
    timestamp - When the error was signaled
    context - Plist with contextual information

  See Also:
    SWARM-UNREACHABLE, SWARM-DISCONNECTED, ROUTING-ERROR, ENVELOPE-ERROR"))

;;;; ============================================================================
;;;; Swarm Connectivity Errors
;;;; ============================================================================

(define-condition swarm-unreachable (sw4rm-error)
  ((swarm-id
    :initarg :swarm-id
    :reader swarm-unreachable-swarm-id
    :type string
    :documentation "ID of the unreachable swarm.")

   (last-seen
    :initarg :last-seen
    :reader swarm-unreachable-last-seen
    :initform nil
    :type (or null integer)
    :documentation "Universal time when this swarm was last seen healthy.

    NIL if the swarm has never been reachable. Used to distinguish between
    newly unreachable and persistently unreachable swarms."))

  (:report (lambda (condition stream)
             (let ((last-seen (swarm-unreachable-last-seen condition)))
               (if last-seen
                   (format stream "Swarm ~S unreachable (last seen ~A seconds ago)"
                           (swarm-unreachable-swarm-id condition)
                           (- (get-universal-time) last-seen))
                   (format stream "Swarm ~S unreachable (never seen)"
                           (swarm-unreachable-swarm-id condition))))))

  (:documentation "Condition signaled when a target swarm cannot be reached.

  This is raised when:
    - The swarm has no active gRPC connection
    - The swarm failed to respond to heartbeat probes
    - The swarm is known but in a failed/degraded state

  Restarts available:
    RETRY-WITH-BACKOFF - Retry delivery with exponential backoff
    ROUTE-TO-ALTERNATIVE - Route to an alternative swarm
    QUEUE-FOR-RETRY - Queue envelope for later delivery
    DEAD-LETTER - Send to dead letter queue
    DROP-MESSAGE - Drop silently (for non-critical messages)

  Slots:
    swarm-id - ID of the unreachable swarm
    last-seen - Timestamp of last successful heartbeat

  See Also:
    SWARM-DISCONNECTED, RETRY-WITH-BACKOFF, ROUTE-TO-ALTERNATIVE"))

(define-condition swarm-disconnected (sw4rm-error)
  ((swarm-id
    :initarg :swarm-id
    :reader swarm-disconnected-swarm-id
    :type string
    :documentation "ID of the disconnected swarm.")

   (reason
    :initarg :reason
    :reader swarm-disconnected-reason
    :initform :unknown
    :type (member :timeout :refused :reset :unknown)
    :documentation "Reason for disconnection.

    Values:
      :TIMEOUT - Connection attempt timed out
      :REFUSED - Server refused connection
      :RESET - Connection was reset by peer
      :UNKNOWN - Reason is unknown"))

  (:report (lambda (condition stream)
             (format stream "Swarm ~S disconnected (~A)"
                     (swarm-disconnected-swarm-id condition)
                     (swarm-disconnected-reason condition))))

  (:documentation "Condition signaled when an active connection is lost.

  This is different from SWARM-UNREACHABLE:
    - SWARM-UNREACHABLE: Target was never reachable
    - SWARM-DISCONNECTED: We had a connection that failed

  This distinction is important for recovery strategies.

  Restarts available:
    RETRY-WITH-BACKOFF - Attempt to reconnect
    ROUTE-TO-ALTERNATIVE - Route to alternative swarm
    QUEUE-FOR-RETRY - Queue for later delivery

  Slots:
    swarm-id - ID of the disconnected swarm
    reason - Why the connection failed

  See Also:
    SWARM-UNREACHABLE, RETRY-WITH-BACKOFF"))

;;;; ============================================================================
;;;; Routing Errors
;;;; ============================================================================

(define-condition routing-error (sw4rm-error)
  ((source
    :initarg :source
    :reader routing-error-source
    :type string
    :documentation "ID of the node where routing failed.")

   (target
    :initarg :target
    :reader routing-error-target
    :type string
    :documentation "Target swarm ID for this envelope.")

   (reason
    :initarg :reason
    :reader routing-error-reason
    :type string
    :documentation "Specific reason routing failed."))

  (:report (lambda (condition stream)
             (format stream "Routing failed: ~A -> ~A (~A)"
                     (routing-error-source condition)
                     (routing-error-target condition)
                     (routing-error-reason condition))))

  (:documentation "Base condition for routing failures.

  Signaled when an envelope cannot be routed to its target swarm.

  Reasons might include:
    - Target swarm not found in routing table
    - All paths to target are blocked
    - Routing decision cannot be made

  Subclasses:
    HOP-LIMIT-EXCEEDED - Hop count limit was reached
    DEADLINE-EXCEEDED - Delivery deadline passed

  See Also:
    HOP-LIMIT-EXCEEDED, DEADLINE-EXCEEDED"))

(define-condition hop-limit-exceeded (routing-error)
  ((hop-count
    :initarg :hop-count
    :reader hop-limit-exceeded-hop-count
    :type (integer 0 *)
    :documentation "Current hop count when limit was exceeded.")

   (max-hops
    :initarg :max-hops
    :reader hop-limit-exceeded-max-hops
    :type (integer 1 *)
    :documentation "Maximum allowed hops."))

  (:report (lambda (condition stream)
             (format stream "Hop limit exceeded (~D/~D hops)"
                     (hop-limit-exceeded-hop-count condition)
                     (hop-limit-exceeded-max-hops condition))))

  (:documentation "Condition signaled when hop limit is exceeded.

  Raised when an envelope has traversed the maximum number of nodes
  without reaching its destination. This prevents infinite loops from
  corrupting the routing table or creating denial of service.

  Hop limits are crucial in mesh networks where routes might be cyclic.

  Typical handling:
    - Dead-letter the envelope
    - Alert ops team
    - Investigate routing table for cycles

  Slots:
    hop-count - Number of hops traversed
    max-hops - Maximum allowed hops

  See Also:
    ROUTING-ERROR, DEAD-LETTER"))

(define-condition deadline-exceeded (routing-error)
  ((deadline
    :initarg :deadline
    :reader deadline-exceeded-deadline
    :type integer
    :documentation "Absolute deadline (universal time) for delivery.")

   (current-time
    :initarg :current-time
    :reader deadline-exceeded-current-time
    :type integer
    :documentation "Current time when deadline was detected."))

  (:report (lambda (condition stream)
             (let ((deadline (deadline-exceeded-deadline condition))
                   (current (deadline-exceeded-current-time condition)))
               (format stream "Deadline exceeded (~D seconds ago)"
                       (- current deadline)))))

  (:documentation "Condition signaled when delivery deadline is exceeded.

  Raised when an envelope's deadline (end time) has passed before delivery.
  This allows applications to enforce time-bounded operations.

  Typical handling:
    - Drop the message
    - Log to audit trail
    - Notify application if configured

  Slots:
    deadline - Absolute deadline (universal time)
    current-time - Time when deadline was detected

  See Also:
    ROUTING-ERROR, DROP-MESSAGE"))

;;;; ============================================================================
;;;; Envelope Structure Errors
;;;; ============================================================================

(define-condition envelope-error (sw4rm-error)
  ((envelope-id
    :initarg :envelope-id
    :reader envelope-error-envelope-id
    :type string
    :documentation "ID of the malformed envelope.")

   (field
    :initarg :field
    :reader envelope-error-field
    :initform nil
    :type (or null symbol)
    :documentation "Field name that failed validation (NIL if general)."))

  (:report (lambda (condition stream)
             (let ((field (envelope-error-field condition)))
               (if field
                   (format stream "Envelope ~S validation failed: ~A"
                           (envelope-error-envelope-id condition)
                           field)
                   (format stream "Envelope ~S malformed"
                           (envelope-error-envelope-id condition))))))

  (:documentation "Base condition for envelope structure/validation errors.

  Raised when:
    - Envelope is missing required fields
    - Field values are out of acceptable ranges
    - Envelope cannot be serialized
    - Payload is corrupted

  This is used for structural validation at the orchestration layer,
  not for application-level validation.

  See Also:
    ROUTING-ERROR, SWARM-UNREACHABLE"))

;;;; ============================================================================
;;;; Idempotent Delivery Error
;;;; ============================================================================

(define-condition idempotent-delivery-error (envelope-error)
  ((previous-result
    :initarg :previous-result
    :reader idempotent-delivery-error-previous-result
    :initform nil
    :type t
    :documentation "Result of the previous delivery attempt.

    This allows the handler to return the same result, ensuring
    true idempotency: f(f(x)) = f(x)"))

  (:report (lambda (condition stream)
             (format stream "Envelope ~S already delivered (idempotent)"
                     (envelope-error-envelope-id condition))))

  (:documentation "Condition signaled when same envelope is delivered twice.

  Raised when an envelope with the same idempotency token is delivered
  to the same target. This can happen due to network retries or
  operator intervention.

  Common Lisp allows the handler to invoke a restart that returns the
  previous result, making the delivery truly idempotent.

  Idempotency is crucial for at-least-once delivery semantics.

  Slots:
    previous-result - Result from the first delivery attempt

  See Also:
    ENVELOPE-ERROR, INVOKE-RESTART"))

;;;; ============================================================================
;;;; End-to-End Delivery Error
;;;; ============================================================================

(define-condition delivery-failed (sw4rm-error)
  ((target-swarm
    :initarg :target-swarm
    :reader delivery-failed-target-swarm
    :type string
    :documentation "Target swarm where delivery failed.")

   (attempts
    :initarg :attempts
    :reader delivery-failed-attempts
    :type (integer 1 *)
    :documentation "Number of delivery attempts made.")

   (last-error
    :initarg :last-error
    :reader delivery-failed-last-error
    :initform nil
    :type (or null condition)
    :documentation "The nested condition from the last attempt.

    This allows handlers to examine what went wrong in detail.
    Examples: SWARM-UNREACHABLE, DEADLINE-EXCEEDED, etc."))

  (:report (lambda (condition stream)
             (format stream "Delivery to ~S failed after ~D attempts~@[: ~A~]"
                     (delivery-failed-target-swarm condition)
                     (delivery-failed-attempts condition)
                     (delivery-failed-last-error condition))))

  (:documentation "Condition signaled when envelope delivery is exhausted.

  This is raised after all retry strategies have been exhausted:
    - Exponential backoff retries completed
    - Alternative routes all failed
    - Deadline passed
    - Operator-initiated failure

  This is the final state before dead-lettering or dropping the message.

  Slots:
    target-swarm - Where we tried to deliver
    attempts - How many attempts were made
    last-error - The nested error from the last attempt

  See Also:
    SWARM-UNREACHABLE, DEADLINE-EXCEEDED, RETRY-WITH-BACKOFF"))

;;;; ============================================================================
;;;; Coordination Errors
;;;; ============================================================================

(define-condition coordination-error (sw4rm-error)
  ((operation
    :initarg :operation
    :reader coordination-error-operation
    :type keyword
    :documentation "Type of coordination operation that failed.

    Examples: :BARRIER, :LEASE, :ARTIFACT-REGISTRY")

   (participants
    :initarg :participants
    :reader coordination-error-participants
    :initform nil
    :type list
    :documentation "Swarm IDs involved in the failed coordination."))

  (:report (lambda (condition stream)
             (format stream "Coordination error (~A operation)"
                     (coordination-error-operation condition))))

  (:documentation "Condition for cross-swarm coordination failures.

  Raised when multi-swarm coordination operations fail:
    - Barrier synchronization timeout
    - Distributed lock acquisition timeout
    - Artifact registry inconsistency

  Slots:
    operation - Type of coordination operation (:BARRIER, :LEASE, etc.)
    participants - List of swarm IDs involved

  See Also:
    CREATE-BARRIER, ACQUIRE-LEASE, REGISTER-ARTIFACT"))

;;;; ============================================================================
;;;; Condition Predicates and Utilities
;;;; ============================================================================

(defun sw4rm-error-p (object)
  "Check if object is an SW4RM-ERROR condition.

  Args:
    object - Any Lisp object

  Returns:
    T if object is an instance of SW4RM-ERROR or its subclasses, NIL otherwise.

  Examples:
    (sw4rm-error-p (make-condition 'swarm-unreachable :swarm-id \"leaf-a\")) => T
    (sw4rm-error-p (make-condition 'error)) => NIL

  See Also:
    SWARM-UNREACHABLE, ROUTING-ERROR, ENVELOPE-ERROR"
  (typep object 'sw4rm-error))

(defun swarm-unreachable-p (object)
  "Check if object is a SWARM-UNREACHABLE condition.

  Args:
    object - Any Lisp object

  Returns:
    T if object is an instance of SWARM-UNREACHABLE, NIL otherwise.

  See Also:
    SW4RM-ERROR-P, SWARM-DISCONNECTED"
  (typep object 'swarm-unreachable))

(defun routing-error-p (object)
  "Check if object is a ROUTING-ERROR or its subclasses.

  Args:
    object - Any Lisp object

  Returns:
    T if object is an instance of ROUTING-ERROR (or subclasses), NIL otherwise.

  See Also:
    HOP-LIMIT-EXCEEDED, DEADLINE-EXCEEDED, ENVELOPE-ERROR"
  (typep object 'routing-error))

(defun error-context-get (condition key &optional default)
  "Get a value from the error context plist.

  Args:
    condition - An SW4RM-ERROR instance
    key - Keyword to look up in context
    default - Default value if key not found

  Returns:
    Value associated with key, or default.

  Examples:
    (error-context-get condition :envelope-id \"unknown\")
    (error-context-get condition :attempt)

  See Also:
    ERROR-CONTEXT, SW4RM-ERROR"
  (declare (type sw4rm-error condition))
  (getf (error-context condition) key default))

(defun copy-condition-with-context (condition &rest context-pairs)
  "Create a copy of condition with additional context.

  This creates a new condition instance with updated context, useful
  for enriching errors as they propagate up the call stack.

  Args:
    condition - SW4RM-ERROR to copy
    context-pairs - Alternating keys and values to add to context

  Returns:
    New condition instance with merged context.

  Example:
    (copy-condition-with-context
      original-error
      :current-node \"node-b\"
      :hop-number 3)

  See Also:
    ERROR-CONTEXT, SW4RM-ERROR"
  (declare (type sw4rm-error condition))
  (let ((existing-context (error-context condition))
        (new-context context-pairs))
    (apply #'make-condition
           (type-of condition)
           :message (sw4rm-error-message condition)
           :context (append new-context existing-context)
           (loop for slot in (mapcar #'sb-mop:slot-definition-name
                                      (sb-mop:class-slots (class-of condition)))
                 when (slot-boundp condition slot)
                 append (list (intern (string-upcase (string slot)) :keyword)
                              (slot-value condition slot))))))

;;;; ============================================================================
;;;; End of file
;;;; ============================================================================
