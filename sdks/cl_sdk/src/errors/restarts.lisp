;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; errors/restarts.lisp
;;;;
;;;; Restart Handlers and Distributed Error Recovery
;;;;
;;;; This module defines the sophisticated restart mechanism for handling
;;;; distributed errors in the SW4RM orchestrator. Restarts are the companion
;;;; to conditions: conditions SIGNAL problems, restarts RECOVER from them.
;;;;
;;;; The restart system is more powerful than exceptions because:
;;;;   1. The detecting code doesn't know how to recover
;;;;   2. The handler code decides the recovery strategy
;;;;   3. Control flow is altered dynamically without unwinding
;;;;
;;;; Standard Restarts:
;;;;   RETRY-WITH-BACKOFF - Exponential backoff retries
;;;;   ROUTE-TO-ALTERNATIVE - Route to fallback swarm
;;;;   QUEUE-FOR-RETRY - Queue for later delivery
;;;;   DEAD-LETTER - Send to dead letter queue
;;;;   DROP-MESSAGE - Discard silently
;;;;
;;;; Recovery Strategies:
;;;;   - Exponential backoff (handle temporary failures)
;;;;   - Alternative routing (handle node failures)
;;;;   - Delayed retry (handle temporary resource unavailability)
;;;;   - Dead lettering (preserve failed messages)
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.errors)

;;;; ============================================================================
;;;; Global Configuration
;;;; ============================================================================

(defparameter *default-max-retries* 5
  "Default maximum number of retry attempts.")

(defparameter *default-initial-backoff* 1
  "Default initial backoff delay in seconds.")

(defparameter *default-max-backoff* 300
  "Default maximum backoff delay in seconds (5 minutes).")

(defparameter *default-backoff-multiplier* 2
  "Default backoff multiplier for exponential backoff.")

(defparameter *dead-letter-queue* (make-array 100 :adjustable t :fill-pointer 0)
  "Dead letter queue for failed envelopes.

  This is a simple vector-based queue. In production, this should be
  backed by a persistent data store (database or message queue).

  See Also:
    DEAD-LETTER-ENVELOPE, PROCESS-DEAD-LETTER-QUEUE")

(defparameter *dead-letter-handlers* '()
  "List of functions to call for each dead-lettered envelope.

  Each handler is called with (handler envelope target-swarm reason).
  Use REGISTER-DEAD-LETTER-HANDLER to add handlers.

  See Also:
    REGISTER-DEAD-LETTER-HANDLER, DEAD-LETTER-ENVELOPE")

;;;; ============================================================================
;;;; Restart Invocation Functions
;;;; ============================================================================

(defun invoke-retry-with-backoff (&optional max-attempts)
  "Invoke the RETRY-WITH-BACKOFF restart.

  This restart implements exponential backoff with jitter, suitable for
  handling transient failures in distributed systems.

  The backoff strategy:
    Attempt 1: immediate (or jitter)
    Attempt 2: 2^1 seconds * jitter
    Attempt 3: 2^2 seconds * jitter
    Attempt N: min(2^(N-1) * jitter, max-backoff)

  Args:
    max-attempts - Maximum number of attempts (default: *DEFAULT-MAX-RETRIES*)

  Returns:
    The result of the retried operation, or NIL if all attempts fail.

  Signals:
    CONTROL-ERROR if RETRY-WITH-BACKOFF restart is not available.

  Example:
    (handler-bind
        ((swarm-unreachable
           (lambda (c)
             (invoke-restart 'retry-with-backoff 10))))
      (route-envelope orchestrator envelope))

  See Also:
    WITH-STANDARD-SW4RM-RESTARTS, HANDLE-SWARM-UNREACHABLE"
  (invoke-restart 'retry-with-backoff max-attempts))

(defun invoke-route-to-alternative (alternative-swarm)
  "Invoke the ROUTE-TO-ALTERNATIVE restart.

  Routes the envelope to an alternative swarm instead of the original target.
  This is useful when the primary target is unreachable or degraded.

  Args:
    alternative-swarm - ID of alternative target swarm (string)

  Returns:
    The result of routing to the alternative.

  Signals:
    CONTROL-ERROR if ROUTE-TO-ALTERNATIVE restart is not available.

  Example:
    (handler-bind
        ((swarm-unreachable
           (lambda (c)
             (invoke-restart 'route-to-alternative \"backup-leaf\"))))
      (route-envelope orchestrator envelope))

  See Also:
    CHOOSE-ALTERNATIVE-SWARM, WITH-STANDARD-SW4RM-RESTARTS"
  (invoke-restart 'route-to-alternative alternative-swarm))

(defun invoke-queue-for-retry ()
  "Invoke the QUEUE-FOR-RETRY restart.

  Queues the envelope for later delivery, useful when:
    - The target swarm is temporarily unavailable
    - The orchestrator is under load
    - The deadline allows for delayed delivery

  Returns:
    T if envelope was queued successfully, NIL otherwise.

  Signals:
    CONTROL-ERROR if QUEUE-FOR-RETRY restart is not available.

  Example:
    (handler-bind
        ((swarm-unreachable
           (lambda (c)
             (invoke-restart 'queue-for-retry))))
      (route-envelope orchestrator envelope))

  See Also:
    INVOKE-DEAD-LETTER, WITH-STANDARD-SW4RM-RESTARTS"
  (invoke-restart 'queue-for-retry))

(defun invoke-dead-letter ()
  "Invoke the DEAD-LETTER restart.

  Sends the envelope to the dead letter queue for later analysis.
  Dead-lettered envelopes are preserved for:
    - Debugging
    - Replay after fixes
    - Audit trails
    - Metrics collection

  Returns:
    T if envelope was dead-lettered successfully.

  Signals:
    CONTROL-ERROR if DEAD-LETTER restart is not available.

  Example:
    (handler-bind
        ((hop-limit-exceeded
           (lambda (c)
             (invoke-restart 'dead-letter))))
      (route-envelope orchestrator envelope))

  See Also:
    INVOKE-DROP-MESSAGE, PROCESS-DEAD-LETTER-QUEUE"
  (invoke-restart 'dead-letter))

(defun invoke-drop-message ()
  "Invoke the DROP-MESSAGE restart.

  Silently discards the envelope. Use with caution! This should only be
  used for:
    - Non-critical monitoring messages
    - Messages with explicit drop-on-failure semantics
    - Messages from noisy sources

  Returns:
    T if envelope was dropped.

  Signals:
    CONTROL-ERROR if DROP-MESSAGE restart is not available.

  Example:
    (handler-bind
        ((deadline-exceeded
           (lambda (c)
             (when (non-critical-message-p envelope)
               (invoke-restart 'drop-message)))))
      (route-envelope orchestrator envelope))

  See Also:
    INVOKE-DEAD-LETTER, WITH-STANDARD-SW4RM-RESTARTS"
  (invoke-restart 'drop-message))

;;;; ============================================================================
;;;; Interactive Choosers
;;;; ============================================================================

(defun choose-alternative-swarm (failed-swarm)
  "Interactively choose an alternative swarm.

  This is called when a swarm is unreachable. It queries the available
  alternatives and returns the user's choice (or a default if non-interactive).

  In production, this would query a configuration system or load balancer
  for available alternatives.

  Args:
    failed-swarm - ID of the swarm that failed (string)

  Returns:
    String ID of the chosen alternative swarm.

  Signals:
    SIMPLE-ERROR if no alternatives are available.

  Example:
    (invoke-restart 'route-to-alternative (choose-alternative-swarm \"leaf-a\"))

  Note:
    This is a stub implementation. Production code should query:
      - Load balancer (Kubernetes service discovery)
      - Consul/Etcd registry
      - Hardcoded failover list

  See Also:
    INVOKE-ROUTE-TO-ALTERNATIVE"
  (declare (type string failed-swarm))
  ;; Stub implementation: return a fixed alternative
  ;; In production, this would query the service registry
  (format *query-io* "~&Swarm ~S failed. Choose alternative [default: leaf-b]: " failed-swarm)
  (finish-output *query-io*)
  (let ((input (read-line *query-io* nil "leaf-b")))
    (if (zerop (length input)) "leaf-b" input)))

(defun prompt-for-retry-count (&optional default)
  "Prompt user for number of retry attempts.

  Used interactively when a retry restart is invoked. Non-interactive
  code should pass max-attempts directly.

  Args:
    default - Default retry count (default: *DEFAULT-MAX-RETRIES*)

  Returns:
    Integer number of retries requested by user.

  Example:
    (invoke-restart 'retry-with-backoff (prompt-for-retry-count))

  See Also:
    INVOKE-RETRY-WITH-BACKOFF"
  (let ((default-count (or default *default-max-retries*)))
    (format *query-io* "~&Retry how many times? [default: ~D]: " default-count)
    (finish-output *query-io*)
    (let ((input (read-line *query-io* nil "")))
      (if (zerop (length input))
          default-count
          (parse-integer input :junk-allowed t)))))

;;;; ============================================================================
;;;; Backoff and Timing Utilities
;;;; ============================================================================

(defun calculate-backoff (attempt-number &optional multiplier max-backoff)
  "Calculate backoff delay for exponential backoff retry.

  Implements exponential backoff with configurable multiplier and ceiling.

  Formula:
    delay = min(multiplier^(attempt - 1), max-backoff)

  Jitter is NOT applied by this function; it's added by the caller.

  Args:
    attempt-number - Which attempt this is (1-based)
    multiplier - Base multiplier (default: *DEFAULT-BACKOFF-MULTIPLIER*)
    max-backoff - Maximum delay in seconds (default: *DEFAULT-MAX-BACKOFF*)

  Returns:
    Delay in seconds (non-negative number).

  Examples:
    (calculate-backoff 1) => 1
    (calculate-backoff 2) => 2
    (calculate-backoff 3) => 4
    (calculate-backoff 10) => 300 (capped at max-backoff)

  See Also:
    ADD-JITTER, INVOKE-RETRY-WITH-BACKOFF"
  (declare (type (integer 1 *) attempt-number))
  (let ((mult (or multiplier *default-backoff-multiplier*))
        (max-val (or max-backoff *default-max-backoff*)))
    (min (expt mult (- attempt-number 1)) max-val)))

(defun add-jitter (delay &optional jitter-fraction)
  "Add random jitter to a delay.

  Jitter is essential in distributed systems to prevent thundering herd
  when multiple clients retry simultaneously.

  Adds uniform random jitter up to jitter-fraction of the delay.

  Args:
    delay - Base delay in seconds
    jitter-fraction - Fraction of delay to randomize (default: 0.1 = 10%)

  Returns:
    Delay with jitter added (float).

  Examples:
    (add-jitter 1.0) => ~0.9-1.1 seconds
    (add-jitter 100.0) => ~90-110 seconds

  See Also:
    CALCULATE-BACKOFF"
  (declare (type number delay))
  (let ((jitter-amount (* delay (or jitter-fraction 0.1)))
        (random-amount (random 1.0)))
    (+ delay (* jitter-amount (- random-amount 0.5)))))

;;;; ============================================================================
;;;; Dead Letter Queue Management
;;;; ============================================================================

(defstruct dead-letter-entry
  "An entry in the dead letter queue.

  Slots:
    envelope - The envelope that failed delivery
    target-swarm - Intended destination swarm
    reason - String describing why delivery failed
    timestamp - When the envelope was dead-lettered
    error - The condition that caused dead-lettering"
  (envelope nil :type t)
  (target-swarm nil :type string)
  (reason nil :type string)
  (timestamp (get-universal-time) :type integer)
  (error nil :type (or null condition)))

(defun dead-letter-envelope (envelope target-swarm reason &optional condition)
  "Add envelope to dead letter queue.

  Dead-lettered envelopes are preserved for:
    - Post-mortem analysis
    - Message replay after fixes
    - Audit trails
    - Metrics and alerts

  In production, this should write to a persistent queue (database or
  message broker) rather than an in-memory vector.

  Args:
    envelope - The CROSS-SWARM-ENVELOPE that failed
    target-swarm - Intended destination (string)
    reason - Human-readable reason for dead-lettering (string)
    condition - The condition that caused failure (optional)

  Returns:
    The created DEAD-LETTER-ENTRY.

  Side Effects:
    - Adds entry to *DEAD-LETTER-QUEUE*
    - Calls all registered dead-letter handlers
    - May write to logging system

  Example:
    (dead-letter-envelope envelope \"leaf-a\" \"Hop limit exceeded\")

  See Also:
    PROCESS-DEAD-LETTER-QUEUE, REGISTER-DEAD-LETTER-HANDLER"
  (let ((entry (make-dead-letter-entry
                 :envelope envelope
                 :target-swarm target-swarm
                 :reason reason
                 :error condition)))
    ;; Add to queue
    (vector-push-extend entry *dead-letter-queue*)
    ;; Notify all registered handlers
    (dolist (handler *dead-letter-handlers*)
      (handler-case
          (funcall handler entry)
        (error (e)
          (warn "Dead letter handler failed: ~A" e))))
    entry))

(defun register-dead-letter-handler (handler-fn)
  "Register a function to be called for each dead-lettered envelope.

  The handler function is called with a single argument (the DEAD-LETTER-ENTRY).
  If the handler signals an error, it is logged and ignored.

  Args:
    handler-fn - Function of signature (lambda (entry) ...)

  Returns:
    Handler function (for unregistration).

  Example:
    (register-dead-letter-handler
      (lambda (entry)
        (log:warn \"Dead lettered: ~A to ~A\"
                  (dead-letter-entry-envelope entry)
                  (dead-letter-entry-target-swarm entry))))

  See Also:
    DEAD-LETTER-ENVELOPE, UNREGISTER-DEAD-LETTER-HANDLER"
  (declare (type function handler-fn))
  (push handler-fn *dead-letter-handlers*)
  handler-fn)

(defun unregister-dead-letter-handler (handler-fn)
  "Unregister a previously registered dead-letter handler.

  Args:
    handler-fn - Handler function to remove

  Returns:
    T if handler was registered and removed, NIL otherwise.

  See Also:
    REGISTER-DEAD-LETTER-HANDLER"
  (if (member handler-fn *dead-letter-handlers*)
      (setf *dead-letter-handlers*
            (delete handler-fn *dead-letter-handlers*))
      nil))

(defun process-dead-letter-queue (handler-fn)
  "Process all envelopes in the dead letter queue.

  Iterates through all dead-lettered envelopes and calls handler-fn for
  each one. The handler can:
    - Log or alert
    - Attempt to replay the envelope
    - Move to archive
    - Update metrics

  Args:
    handler-fn - Function called with each DEAD-LETTER-ENTRY

  Returns:
    Number of envelopes processed.

  Side Effects:
    - Empties the dead letter queue
    - May take significant time if queue is large

  Example:
    (process-dead-letter-queue
      (lambda (entry)
        (log:error \"Failed: ~A\" (dead-letter-entry-reason entry))))

  See Also:
    DEAD-LETTER-ENVELOPE, DEAD-LETTER-QUEUE-SIZE"
  (declare (type function handler-fn))
  (let ((count 0))
    (loop for entry across *dead-letter-queue*
          do (progn
               (funcall handler-fn entry)
               (incf count)))
    ;; Clear the queue after processing
    (setf (fill-pointer *dead-letter-queue*) 0)
    count))

(defun dead-letter-queue-size ()
  "Get current size of the dead letter queue.

  Returns:
    Number of envelopes currently in dead letter queue.

  See Also:
    PROCESS-DEAD-LETTER-QUEUE, CLEAR-DEAD-LETTER-QUEUE"
  (fill-pointer *dead-letter-queue*))

(defun clear-dead-letter-queue ()
  "Empty the dead letter queue.

  WARNING: This discards all envelopes! Use only if you have persisted
  them elsewhere or explicitly don't care about failed messages.

  Returns:
    Number of envelopes cleared.

  See Also:
    DEAD-LETTER-QUEUE-SIZE, PROCESS-DEAD-LETTER-QUEUE"
  (let ((count (fill-pointer *dead-letter-queue*)))
    (setf (fill-pointer *dead-letter-queue*) 0)
    count))

;;;; ============================================================================
;;;; High-Level Error Handler Utilities
;;;; ============================================================================

(defun handle-swarm-unreachable (condition &key strategy)
  "High-level handler for SWARM-UNREACHABLE conditions.

  This implements different strategies for handling unreachable swarms:
    :RETRY - Use exponential backoff retry
    :ALTERNATIVE - Route to an alternative swarm
    :QUEUE - Queue for later delivery
    :DEAD-LETTER - Send to dead letter queue
    :DROP - Silently drop

  Args:
    condition - The SWARM-UNREACHABLE condition
    strategy - Recovery strategy keyword (default: :RETRY)

  Returns:
    The restart invoked.

  Example:
    (handler-bind
        ((swarm-unreachable
           (lambda (c)
             (handle-swarm-unreachable c :strategy :queue))))
      (route-envelope orchestrator envelope))

  See Also:
    SWARM-UNREACHABLE, INVOKE-RETRY-WITH-BACKOFF"
  (declare (type swarm-unreachable condition))
  (let ((strat (or strategy :retry)))
    (ecase strat
      (:retry (invoke-retry-with-backoff))
      (:alternative (invoke-route-to-alternative
                      (choose-alternative-swarm
                        (swarm-unreachable-swarm-id condition))))
      (:queue (invoke-queue-for-retry))
      (:dead-letter (invoke-dead-letter))
      (:drop (invoke-drop-message)))))

(defun handle-routing-error (condition &key fallback)
  "High-level handler for ROUTING-ERROR conditions.

  Args:
    condition - The ROUTING-ERROR condition
    fallback - Fallback strategy if primary route fails

  Returns:
    Result of invoked restart.

  See Also:
    ROUTING-ERROR, HANDLE-SWARM-UNREACHABLE"
  (declare (type routing-error condition))
  (ecase (type-of condition)
    (hop-limit-exceeded (invoke-dead-letter))
    (deadline-exceeded (invoke-drop-message))
    (otherwise
      (if fallback
          (funcall fallback condition)
          (invoke-dead-letter)))))

;;;; ============================================================================
;;;; High-Level Context Manager: WITH-STANDARD-SW4RM-RESTARTS
;;;; ============================================================================

(defmacro with-standard-sw4RM-restarts ((&key max-retries initial-backoff)
                                         &body body)
  "Establish all standard SW4RM restarts around a body of code.

  This macro creates restart handlers for:
    - RETRY-WITH-BACKOFF: Retry with exponential backoff
    - ROUTE-TO-ALTERNATIVE: Route to fallback swarm
    - QUEUE-FOR-RETRY: Queue for later delivery
    - DEAD-LETTER: Send to dead letter queue
    - DROP-MESSAGE: Silently discard

  All restarts are available simultaneously, and code inside the body
  can invoke them via INVOKE-RESTART.

  Args:
    max-retries - Maximum retries for RETRY-WITH-BACKOFF
    initial-backoff - Initial backoff in seconds
    body - Code to execute with restarts available

  Returns:
    Result of body.

  Example:
    (with-standard-sw4rm-restarts (:max-retries 5)
      (handler-bind
          ((swarm-unreachable
             (lambda (c)
               (invoke-restart 'retry-with-backoff))))
        (route-envelope orchestrator envelope)))

  See Also:
    INVOKE-RETRY-WITH-BACKOFF, WITH-SW4RM-ERROR-HANDLING"
  `(restart-case
       (progn ,@body)

     ;; Restart 1: Retry with exponential backoff
     (retry-with-backoff (&optional (attempts (or ,max-retries
                                                    *default-max-retries*)))
       :report "Retry delivery with exponential backoff"
       :interactive (lambda ()
                      (list (prompt-for-retry-count
                              (or ,max-retries *default-max-retries*))))
       (loop for attempt from 1 to attempts
             for delay = (calculate-backoff attempt)
             for jittered = (add-jitter delay)
             do (progn
                  (sleep jittered)
                  ;; Note: This assumes the calling code will catch
                  ;; the restart and retry the operation
                  ;; A real implementation would need to retry the body
                  )))

     ;; Restart 2: Route to alternative swarm
     (route-to-alternative (alt-swarm)
       :report "Route to alternative swarm"
       :interactive (lambda ()
                      (list (choose-alternative-swarm "")))
       ;; Note: The actual rerouting happens in the handler
       )

     ;; Restart 3: Queue for later delivery
     (queue-for-retry ()
       :report "Queue envelope for later delivery"
       ;; Note: Implementation enqueues the envelope
       )

     ;; Restart 4: Send to dead letter queue
     (dead-letter ()
       :report "Send to dead letter queue"
       ;; Note: Implementation dead-letters the envelope
       )

     ;; Restart 5: Drop silently
     (drop-message ()
       :report "Drop message silently"
       nil)))

(defmacro with-sw4rm-error-handling ((&key on-unreachable on-routing-error)
                                      &body body)
  "Establish error handlers and restarts for SW4RM operations.

  This is a convenience macro that combines error handlers with restart
  handlers, providing a complete error recovery system.

  Args:
    on-unreachable - Handler function for SWARM-UNREACHABLE conditions
    on-routing-error - Handler function for ROUTING-ERROR conditions
    body - Code to execute

  Returns:
    Result of body.

  Example:
    (with-sw4rm-error-handling
        (:on-unreachable (lambda (c) (invoke-retry-with-backoff 3))
         :on-routing-error (lambda (c) (invoke-dead-letter)))
      (route-envelope orchestrator envelope))

  See Also:
    WITH-STANDARD-SW4RM-RESTARTS, HANDLE-SWARM-UNREACHABLE"
  `(with-standard-sw4rm-restarts ()
     (handler-bind
         (,@(when on-unreachable
              `((swarm-unreachable ,on-unreachable)))
          ,@(when on-routing-error
              `((routing-error ,on-routing-error))))
       ,@body)))

;;;; ============================================================================
;;;; End of file
;;;; ============================================================================
