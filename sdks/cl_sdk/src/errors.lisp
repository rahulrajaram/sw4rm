;;;; errors.lisp - Error condition hierarchy with restart support

(in-package #:sw4rm)

;;;; Base Condition
;;;
;;; SW4RM uses Common Lisp's condition system for error handling, providing
;;; structured error information with restart support for recovery.

(define-condition sw4rm-error (error)
  ((message
    :initarg :message
    :reader sw4rm-error-message
    :type string
    :documentation "Human-readable error description.")
   (error-code
    :initarg :error-code
    :initform +internal-error+
    :reader sw4rm-error-error-code
    :type integer
    :documentation "Protocol error code from constants."))
  (:documentation "Base condition for all SW4RM protocol errors.

This is the root of the SW4RM condition hierarchy. All SDK errors inherit from
this condition to enable catch-all error handling with (handler-case ... (sw4rm-error ...)).

The condition system provides structured error information with protocol error codes
for interoperability and automated error handling.")
  (:report (lambda (condition stream)
             (format stream "SW4RM Error [~A]: ~A"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)))))

;;;; RPC Errors
;;;
;;; Errors related to gRPC communication failures.

(define-condition rpc-error (sw4rm-error)
  ((status-code
    :initarg :status-code
    :reader rpc-error-status-code
    :type string
    :documentation "gRPC status code (e.g., UNAVAILABLE, DEADLINE_EXCEEDED).")
   (details
    :initarg :details
    :reader rpc-error-details
    :type string
    :documentation "Detailed error information from gRPC layer."))
  (:default-initargs :error-code +no-route+)
  (:documentation "Condition for gRPC communication failures.

Raised when gRPC calls fail due to network issues, service unavailability,
or protocol errors. Contains gRPC-specific status information for debugging.")
  (:report (lambda (condition stream)
             (format stream "RPC Error [~A/~A]: ~A - ~A"
                     (rpc-error-status-code condition)
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (rpc-error-details condition)))))

;;;; Validation Errors
;;;
;;; Errors related to input validation failures.

(define-condition validation-error (sw4rm-error)
  ((field
    :initarg :field
    :reader validation-error-field
    :type string
    :documentation "Name of the field that failed validation.")
   (constraint
    :initarg :constraint
    :reader validation-error-constraint
    :type string
    :documentation "Description of the violated constraint."))
  (:default-initargs :error-code +validation-error+)
  (:documentation "Condition for input validation failures.

Raised when user input or API parameters fail validation constraints such as
type checks, range checks, or format requirements. Per spec §11, MUST be used
for malformed or invalid message fields.")
  (:report (lambda (condition stream)
             (format stream "Validation Error [~A]: ~A (field: ~A, constraint: ~A)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (validation-error-field condition)
                     (validation-error-constraint condition)))))

;;;; State Machine Errors
;;;
;;; Errors related to invalid state transitions.

(define-condition state-transition-error (sw4rm-error)
  ((from-state
    :initarg :from-state
    :reader state-transition-error-from-state
    :type (or integer string)
    :documentation "Current state before attempted transition.")
   (to-state
    :initarg :to-state
    :reader state-transition-error-to-state
    :type (or integer string)
    :documentation "Requested target state.")
   (allowed-transitions
    :initarg :allowed-transitions
    :reader state-transition-error-allowed-transitions
    :type list
    :documentation "List of valid transitions from current state."))
  (:default-initargs :error-code +internal-error+)
  (:documentation "Condition for invalid agent state transitions.

Raised when attempting to transition an agent to a state that is not allowed
from its current state according to the state machine rules (spec §8).
Includes information about valid transitions for debugging.")
  (:report (lambda (condition stream)
             (format stream "State Transition Error [~A]: ~A (from ~A to ~A, allowed: ~{~A~^, ~})"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (state-transition-error-from-state condition)
                     (state-transition-error-to-state condition)
                     (state-transition-error-allowed-transitions condition)))))

;;;; Timeout Errors
;;;
;;; Errors related to operation timeouts.

(define-condition timeout-error (sw4rm-error)
  ((operation
    :initarg :operation
    :reader timeout-error-operation
    :type string
    :documentation "Name or description of the timed-out operation.")
   (timeout-ms
    :initarg :timeout-ms
    :reader timeout-error-timeout-ms
    :type integer
    :documentation "Timeout duration in milliseconds."))
  (:default-initargs :error-code +ack-timeout+)
  (:documentation "Condition for operation timeouts.

Raised when an operation exceeds its configured timeout duration.
Per spec §11, default acknowledgement timeout is 10 seconds.")
  (:report (lambda (condition stream)
             (format stream "Timeout Error [~A]: ~A (operation: ~A, timeout: ~Ams)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (timeout-error-operation condition)
                     (timeout-error-timeout-ms condition)))))

;;;; Buffer Errors
;;;
;;; Errors related to activity buffer capacity.

(define-condition buffer-full-error (sw4rm-error)
  ((current-size
    :initarg :current-size
    :reader buffer-full-error-current-size
    :type integer
    :documentation "Current number of entries in buffer.")
   (max-size
    :initarg :max-size
    :reader buffer-full-error-max-size
    :type integer
    :documentation "Maximum allowed buffer entries."))
  (:default-initargs :error-code +buffer-full+)
  (:documentation "Condition for activity buffer capacity exceeded.

Per spec §10.1, implementations MUST NOT silently drop entries when limits are
reached; instead, MUST reject new registrations with error_code=BUFFER_FULL.")
  (:report (lambda (condition stream)
             (format stream "Buffer Full Error [~A]: ~A (current: ~A, max: ~A)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (buffer-full-error-current-size condition)
                     (buffer-full-error-max-size condition)))))

;;;; Negotiation Errors
;;;
;;; Errors related to multi-agent negotiation failures.

(define-condition negotiation-error (sw4rm-error)
  ((negotiation-id
    :initarg :negotiation-id
    :reader negotiation-error-negotiation-id
    :type string
    :documentation "Identifier of the failed negotiation.")
   (phase
    :initarg :phase
    :reader negotiation-error-phase
    :type string
    :documentation "Current phase of negotiation (e.g., proposal, voting, consensus)."))
  (:default-initargs :error-code +internal-error+)
  (:documentation "Condition for negotiation protocol failures.

Raised when multi-agent negotiation operations fail, such as proposal rejections,
consensus failures, or protocol violations (spec §17).")
  (:report (lambda (condition stream)
             (format stream "Negotiation Error [~A]: ~A (negotiation: ~A, phase: ~A)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (negotiation-error-negotiation-id condition)
                     (negotiation-error-phase condition)))))

;;;; Worktree Errors
;;;
;;; Errors related to Git worktree management.

(define-condition worktree-error (sw4rm-error)
  ((worktree-id
    :initarg :worktree-id
    :reader worktree-error-worktree-id
    :type string
    :documentation "Identifier of the affected worktree.")
   (state
    :initarg :state
    :reader worktree-error-state
    :type (or integer string)
    :documentation "Current worktree state."))
  (:default-initargs :error-code +internal-error+)
  (:documentation "Condition for worktree binding and management failures.

Raised when worktree operations fail, such as binding failures, state
inconsistencies, or resource conflicts (spec §16).")
  (:report (lambda (condition stream)
             (format stream "Worktree Error [~A]: ~A (worktree: ~A, state: ~A)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (worktree-error-worktree-id condition)
                     (worktree-error-state condition)))))

;;;; Idempotency Errors
;;;
;;; Errors related to duplicate detection and idempotency.

(define-condition duplicate-detected-error (sw4rm-error)
  ((idempotency-token
    :initarg :idempotency-token
    :reader duplicate-detected-error-idempotency-token
    :type string
    :documentation "The duplicate idempotency token."))
  (:default-initargs :error-code +duplicate-detected+)
  (:documentation "Condition for duplicate request detection.

Raised when an idempotency token is reused and maps to a terminal state.
Per spec §11.2, implementations MUST return cached outcomes for duplicate tokens.")
  (:report (lambda (condition stream)
             (format stream "Duplicate Detected [~A]: ~A (token: ~A)"
                     (sw4rm-error-error-code condition)
                     (sw4rm-error-message condition)
                     (duplicate-detected-error-idempotency-token condition)))))

;;;; Error Handling Macros
;;;
;;; Convenience macros for structured error handling with restarts.

(defmacro with-sw4rm-error-handling ((&key (retry-restart 'retry-operation)
                                            (abort-restart 'abort-operation)
                                            (default-handler 'handle-error))
                                      &body body)
  "Execute BODY with standard SW4RM error handling and restarts.

Provides three standard restarts:
- RETRY-RESTART: Retry the failed operation
- ABORT-RESTART: Abort the operation and propagate error
- DEFAULT-HANDLER: Custom error handler for unhandled conditions

Example:
  (with-sw4rm-error-handling (:default-handler #'log-and-continue)
    (send-message envelope))"
  (let ((retry-sym (gensym "RETRY-"))
        (condition-sym (gensym "CONDITION-")))
    `(restart-case
         (handler-bind
             ((sw4rm-error
               (lambda (,condition-sym)
                 (when (fboundp ',default-handler)
                   (funcall ',default-handler ,condition-sym)))))
           ,@body)
       (,retry-restart ()
         :report "Retry the failed operation"
         (,retry-sym))
       (,abort-restart ()
         :report "Abort the operation"
         (error "Operation aborted by user")))))

(defun invoke-sw4rm-restart (restart-name &rest args)
  "Invoke a SW4RM restart by name with optional arguments.

Example:
  (invoke-sw4rm-restart 'retry-operation)"
  (let ((restart (find-restart restart-name)))
    (if restart
        (apply #'invoke-restart restart args)
        (error "No restart named ~A found" restart-name))))
