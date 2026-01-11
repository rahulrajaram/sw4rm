;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; coordination/sync.lisp
;;;;
;;;; Barrier Synchronization for Cross-Swarm Coordination
;;;;
;;;; This module implements distributed barrier synchronization primitives that
;;;; enable multiple sw4rm instances to synchronize at coordination points.
;;;;
;;;; Key concepts:
;;;;   - DISTRIBUTED-BARRIER: A synchronization point where N participants must arrive
;;;;   - Timeout handling: Barriers can expire if not all participants arrive
;;;;   - Callback support: Execute function when barrier completes
;;;;   - Reusable barriers: Barriers can be reset and reused
;;;;
;;;; Barriers are crucial for coordinating multi-swarm workflows:
;;;;   - Wait for all swarms to complete initialization
;;;;   - Synchronize checkpoint creation across swarms
;;;;   - Coordinate distributed transactions
;;;;   - Implement consensus protocols
;;;;
;;;; Thread Safety:
;;;;   This implementation uses bordeaux-threads for thread-safe operations.
;;;;   Multiple threads can safely call barrier operations concurrently.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.coordination)

;;;; ============================================================================
;;;; DISTRIBUTED-BARRIER Class
;;;; ============================================================================

(defclass distributed-barrier ()
  ((id
    :initarg :id
    :reader barrier-id
    :type string
    :documentation "Unique identifier for this barrier.")

   (participants
    :initarg :participants
    :reader barrier-participants
    :type list
    :documentation "List of swarm IDs expected to arrive at this barrier.

    Each participant must call BARRIER-ARRIVE before the barrier completes.")

   (arrived
    :accessor barrier-arrived
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping swarm-id -> arrival timestamp.

    When a participant arrives, their ID and timestamp are recorded here.")

   (timeout
    :initarg :timeout
    :accessor barrier-timeout
    :initform 60
    :type (integer 0)
    :documentation "Timeout in seconds for barrier completion.

    If not all participants arrive within this time, the barrier times out.
    0 means no timeout (wait indefinitely).")

   (callback
    :initarg :callback
    :accessor barrier-callback
    :initform nil
    :type (or null function)
    :documentation "Optional callback function invoked when all participants arrive.

    Called with the barrier instance as argument: (funcall callback barrier)")

   (state
    :accessor barrier-state
    :initform :waiting
    :type (member :waiting :complete :timeout :cancelled)
    :documentation "Current state of the barrier.

    Values:
      :WAITING - Waiting for participants to arrive
      :COMPLETE - All participants arrived successfully
      :TIMEOUT - Timeout expired before all participants arrived
      :CANCELLED - Barrier was explicitly cancelled")

   (created-at
    :reader barrier-created-at
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when barrier was created.")

   (completed-at
    :accessor barrier-completed-at
    :initform nil
    :type (or null integer)
    :documentation "Universal time when barrier completed (or timed out/cancelled).")

   (lock
    :reader barrier-lock
    :initform (bt:make-lock "barrier-lock")
    :documentation "Lock for thread-safe operations on barrier state.")

   (condition-var
    :reader barrier-condition-var
    :initform (bt:make-condition-variable :name "barrier-cv")
    :documentation "Condition variable for blocking wait operations."))

  (:documentation "Distributed barrier for cross-swarm synchronization.

  A barrier is a synchronization primitive where N participants must reach a
  coordination point before any can proceed. This is essential for coordinating
  multi-swarm workflows.

  Lifecycle:
    1. Create barrier with list of expected participants
    2. Each swarm calls BARRIER-ARRIVE when ready
    3. When last swarm arrives, barrier transitions to :COMPLETE
    4. Optional callback is invoked
    5. All waiting threads are woken up
    6. Barrier can be reset for reuse

  States:
    :WAITING - Initial state, waiting for participants
    :COMPLETE - All participants arrived, barrier satisfied
    :TIMEOUT - Timeout expired before completion
    :CANCELLED - Barrier was cancelled

  Operations:
    - BARRIER-ARRIVE: Participant signals arrival
    - BARRIER-WAIT: Block until all participants arrive or timeout
    - BARRIER-RESET: Reset barrier for reuse
    - BARRIER-CANCEL: Cancel barrier and wake all waiters

  Thread Safety:
    All operations are thread-safe and can be called concurrently.

  Example:
    (let ((barrier (make-barrier \"sync-1\"
                                  '(\"swarm-a\" \"swarm-b\" \"swarm-c\")
                                  :timeout 30
                                  :callback (lambda (b)
                                              (format t \"All swarms ready!~%\")))))
      ;; In swarm-a
      (barrier-arrive barrier \"swarm-a\")

      ;; In swarm-b
      (barrier-arrive barrier \"swarm-b\")

      ;; In swarm-c (last one triggers completion)
      (barrier-arrive barrier \"swarm-c\")  ; Callback fires here

      ;; Or block until complete
      (barrier-wait barrier :timeout 60))

  See Also:
    MAKE-BARRIER, BARRIER-ARRIVE, BARRIER-WAIT, BARRIER-RESET"))

;;;; ============================================================================
;;;; Constructor
;;;; ============================================================================

(defun make-barrier (id participants &key (timeout 60) callback)
  "Create a new distributed barrier.

  Args:
    id - Unique string identifier for this barrier
    participants - List of swarm IDs that must arrive
    timeout - Timeout in seconds (default: 60, 0 = no timeout)
    callback - Optional function called when barrier completes

  Returns:
    New DISTRIBUTED-BARRIER instance.

  Raises:
    ERROR if id is empty or participants list is empty

  Examples:
    (make-barrier \"init-sync\" '(\"swarm-a\" \"swarm-b\"))
    (make-barrier \"checkpoint\" '(\"s1\" \"s2\" \"s3\")
                  :timeout 120
                  :callback #'log-checkpoint-ready)

  See Also:
    DISTRIBUTED-BARRIER, BARRIER-ARRIVE, BARRIER-WAIT"
  (unless (and (stringp id) (> (length id) 0))
    (error "Barrier ID must be a non-empty string, got: ~S" id))
  (unless (and (listp participants) (> (length participants) 0))
    (error "Barrier participants must be a non-empty list, got: ~S" participants))
  (when (and callback (not (functionp callback)))
    (error "Barrier callback must be a function, got: ~S" callback))

  (make-instance 'distributed-barrier
                 :id id
                 :participants participants
                 :timeout timeout
                 :callback callback))

;; Compatibility wrapper for tests: accept either (participants &key ...)
;; or (id participants &key ...).
(defun create-barrier (id-or-participants &rest args)
  "Create a distributed barrier with flexible argument order.

  Supports:
    (create-barrier participants &key timeout callback)
    (create-barrier id participants &key timeout callback)"
  (labels ((extract-options (options)
             (values (getf options :timeout 60)
                     (getf options :callback nil)))
           (auto-id ()
             (format nil "barrier-~A" (get-universal-time))))
    (cond
      ;; Signature: (participants &key ...)
      ((and (listp id-or-participants)
            (or (null args) (keywordp (first args))))
       (multiple-value-bind (timeout callback) (extract-options args)
         (make-barrier (auto-id) id-or-participants
                       :timeout timeout
                       :callback callback)))

      ;; Signature: (id participants &key ...)
      ((and (stringp id-or-participants)
            args
            (listp (first args)))
       (let ((participants (first args))
             (options (rest args)))
         (multiple-value-bind (timeout callback) (extract-options options)
           (make-barrier id-or-participants participants
                         :timeout timeout
                         :callback callback))))

      (t
       (error "create-barrier expects (participants &key ...) or (id participants &key ...)")))))

;;;; ============================================================================
;;;; Barrier Operations
;;;; ============================================================================

(defun barrier-arrive (barrier swarm-id)
  "Signal that a participant has arrived at the barrier.

  Records the arrival time for this participant. If this is the last
  participant to arrive, the barrier completes and optional callback is invoked.

  Args:
    barrier - DISTRIBUTED-BARRIER instance
    swarm-id - String ID of arriving swarm

  Returns:
    Two values:
      - arrived-count: Number of participants that have arrived so far
      - remaining: Number of participants still needed

  Raises:
    ERROR if swarm-id is not in the expected participants list
    ERROR if barrier is not in :WAITING state

  Side Effects:
    - Updates barrier-arrived hash table
    - May transition state to :COMPLETE
    - May invoke callback
    - Wakes all waiting threads if barrier completes

  Examples:
    (multiple-value-bind (arrived remaining)
        (barrier-arrive barrier \"swarm-a\")
      (format t \"~D arrived, ~D remaining~%\" arrived remaining))

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-WAIT, BARRIER-COMPLETE-P"
  (declare (type distributed-barrier barrier)
           (type string swarm-id))

  (bt:with-lock-held ((barrier-lock barrier))
    ;; Validate state
    (let ((state (barrier-state barrier)))
      ;; Allow duplicate arrivals after completion as a no-op.
      (when (and (eq state :complete)
                 (gethash swarm-id (barrier-arrived barrier)))
        (return-from barrier-arrive
          (values (hash-table-count (barrier-arrived barrier))
                  0)))
      (unless (eq state :waiting)
        (error "Cannot arrive at barrier ~S in state ~S"
               (barrier-id barrier) state)))

    ;; Validate participant
    (unless (member swarm-id (barrier-participants barrier) :test #'string=)
      (error "Swarm ~S is not a participant in barrier ~S"
             swarm-id (barrier-id barrier)))

    ;; Check for duplicate arrival
    (when (gethash swarm-id (barrier-arrived barrier))
      (warn "Swarm ~S already arrived at barrier ~S (ignoring duplicate)"
            swarm-id (barrier-id barrier))
      (return-from barrier-arrive
        (values (hash-table-count (barrier-arrived barrier))
                (- (length (barrier-participants barrier))
                   (hash-table-count (barrier-arrived barrier))))))

    ;; Record arrival
    (setf (gethash swarm-id (barrier-arrived barrier))
          (get-universal-time))

    (let* ((arrived-count (hash-table-count (barrier-arrived barrier)))
           (total-count (length (barrier-participants barrier)))
           (remaining (- total-count arrived-count)))

      ;; Check if barrier is now complete
      (when (zerop remaining)
        (setf (barrier-state barrier) :complete
              (barrier-completed-at barrier) (get-universal-time))

        ;; Invoke callback if provided
        (when (barrier-callback barrier)
          (funcall (barrier-callback barrier) barrier))

        ;; Wake all waiting threads
        (bt:condition-notify (barrier-condition-var barrier)))

      (values arrived-count remaining))))

(defun barrier-wait (barrier &key (timeout nil))
  "Block until barrier completes or timeout expires.

  Waits for all participants to arrive. If timeout is provided, will stop
  waiting after that many seconds.

  Args:
    barrier - DISTRIBUTED-BARRIER instance
    timeout - Optional timeout in seconds (NIL = use barrier's timeout)

  Returns:
    Two values:
      - success: T if barrier completed, NIL if timed out/cancelled
      - arrivals: Hash table of swarm-id -> arrival-timestamp

  Examples:
    ;; Wait with barrier's default timeout
    (barrier-wait barrier)

    ;; Wait with custom timeout
    (multiple-value-bind (success arrivals)
        (barrier-wait barrier :timeout 120)
      (if success
          (format t \"Barrier completed with ~D arrivals~%\"
                  (hash-table-count arrivals))
          (format t \"Barrier timed out~%\")))

  Thread Safety:
    This operation is thread-safe and can be called by multiple threads.

  See Also:
    BARRIER-ARRIVE, BARRIER-COMPLETE-P, BARRIER-TIMED-OUT-P"
  (declare (type distributed-barrier barrier))

  (let ((effective-timeout (or timeout (barrier-timeout barrier)))
        (start-time (get-universal-time)))

    (bt:with-lock-held ((barrier-lock barrier))
      ;; If already complete/cancelled/timeout, return immediately
      (unless (eq (barrier-state barrier) :waiting)
        (return-from barrier-wait
          (values (eq (barrier-state barrier) :complete)
                  (barrier-arrived barrier))))

      ;; Wait for completion or timeout
      (loop
        (let* ((now (get-universal-time))
               (elapsed (- now start-time))
               (remaining-time (if (zerop effective-timeout)
                                   most-positive-fixnum
                                   (- effective-timeout elapsed))))

          ;; Check if we've timed out
          (when (<= remaining-time 0)
            (setf (barrier-state barrier) :timeout
                  (barrier-completed-at barrier) (get-universal-time))
            (return-from barrier-wait
              (values nil (barrier-arrived barrier))))

          ;; Wait on condition variable
          (bt:condition-wait (barrier-condition-var barrier)
                            (barrier-lock barrier)
                            :timeout remaining-time)

          ;; Check state after waking
          (case (barrier-state barrier)
            (:complete
             (return-from barrier-wait
               (values t (barrier-arrived barrier))))
            (:cancelled
             (return-from barrier-wait
               (values nil (barrier-arrived barrier))))
            (:timeout
             (return-from barrier-wait
               (values nil (barrier-arrived barrier))))))))))

(defun barrier-complete-p (barrier)
  "Check if barrier has completed successfully.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    T if barrier is in :COMPLETE state, NIL otherwise.

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-TIMED-OUT-P, BARRIER-STATE"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (eq (barrier-state barrier) :complete)))

(defun barrier-open-p (barrier)
  "Check if barrier is still open (waiting for participants)."
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (eq (barrier-state barrier) :waiting)))

(defun barrier-cancel (barrier)
  "Cancel the barrier and wake all waiting threads.

  Transitions the barrier to :CANCELLED state and notifies all waiting threads.
  This is typically used for graceful shutdown or error recovery.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    T

  Side Effects:
    - Sets state to :CANCELLED
    - Sets completed-at timestamp
    - Wakes all waiting threads

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-RESET, BARRIER-WAIT"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (setf (barrier-state barrier) :cancelled
          (barrier-completed-at barrier) (get-universal-time))
    (bt:condition-notify (barrier-condition-var barrier)))
  t)

(defun barrier-reset (barrier)
  "Reset the barrier to :WAITING state for reuse.

  Clears all arrival records and resets state to :WAITING. The participant
  list and timeout remain unchanged.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    The barrier instance (for chaining).

  Side Effects:
    - Clears barrier-arrived hash table
    - Sets state to :WAITING
    - Clears completed-at timestamp

  Thread Safety:
    This operation is thread-safe.

  Example:
    ;; Use barrier multiple times
    (dotimes (i 5)
      (barrier-wait barrier)
      (format t \"Round ~D complete~%\" i)
      (barrier-reset barrier))

  See Also:
    BARRIER-CANCEL, MAKE-BARRIER"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (clrhash (barrier-arrived barrier))
    (setf (barrier-state barrier) :waiting
          (barrier-completed-at barrier) nil))
  barrier)

;;;; ============================================================================
;;;; Query Operations
;;;; ============================================================================

(defun barrier-timed-out-p (barrier)
  "Check if barrier has timed out.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    T if barrier is in :TIMEOUT state, NIL otherwise.

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-COMPLETE-P, BARRIER-REMAINING-TIME"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (eq (barrier-state barrier) :timeout)))

(defun barrier-remaining-time (barrier)
  "Calculate remaining time before barrier timeout.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    Remaining seconds as integer, or NIL if no timeout or already completed.

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-TIMEOUT, BARRIER-TIMED-OUT-P"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (when (and (eq (barrier-state barrier) :waiting)
               (> (barrier-timeout barrier) 0))
      (let* ((now (get-universal-time))
             (elapsed (- now (barrier-created-at barrier)))
             (remaining (- (barrier-timeout barrier) elapsed)))
        (max 0 remaining)))))

(defun barrier-participants-arrived (barrier)
  "Get list of participants that have arrived so far.

  Args:
    barrier - DISTRIBUTED-BARRIER instance

  Returns:
    List of swarm IDs that have arrived.

  Thread Safety:
    This operation is thread-safe.

  See Also:
    BARRIER-PARTICIPANTS, BARRIER-ARRIVE"
  (declare (type distributed-barrier barrier))
  (bt:with-lock-held ((barrier-lock barrier))
    (loop for swarm-id being the hash-keys of (barrier-arrived barrier)
          collect swarm-id)))

;;;; ============================================================================
;;;; High-Level Coordination Primitives
;;;; ============================================================================

(defmacro with-barrier ((barrier swarm-id) &body body)
  "Execute body, arrive at barrier, then cleanup.

  This macro ensures barrier arrival happens after body completes,
  even if errors occur. Useful for coordinating work completion.

  Args:
    barrier - DISTRIBUTED-BARRIER instance (evaluated)
    swarm-id - String ID of this swarm (evaluated)
    body - Forms to execute before arriving

  Example:
    (with-barrier (my-barrier \"swarm-a\")
      ;; Do work
      (process-data)
      (compute-results))
    ;; Barrier arrival happens here automatically

  See Also:
    BARRIER-ARRIVE, BARRIER-WAIT"
  `(unwind-protect
       (progn ,@body)
     (barrier-arrive ,barrier ,swarm-id)))

(defun wait-for-swarms (swarms &key (timeout 60))
  "Create a temporary barrier and wait for specified swarms.

  Convenience function for simple synchronization scenarios.

  Args:
    swarms - List of swarm IDs to wait for
    timeout - Timeout in seconds (default: 60)

  Returns:
    Two values:
      - complete: T if all swarms arrived, NIL if timeout
      - missing: List of swarms that didn't arrive (empty if complete)

  Example:
    (multiple-value-bind (complete missing)
        (wait-for-swarms '(\"swarm-a\" \"swarm-b\" \"swarm-c\") :timeout 120)
      (if complete
          (format t \"All swarms ready~%\")
          (format t \"Missing swarms: ~{~A~^, ~}~%\" missing)))

  See Also:
    MAKE-BARRIER, BARRIER-WAIT"
  (let* ((barrier-id (format nil "temp-~A" (get-universal-time)))
         (barrier (make-barrier barrier-id swarms :timeout timeout)))

    (multiple-value-bind (success arrivals)
        (barrier-wait barrier)
      (if success
          (values t nil)
          (let ((arrived-ids (loop for id being the hash-keys of arrivals
                                   collect id)))
            (values nil (set-difference swarms arrived-ids :test #'string=)))))))

(defun rendezvous-point (participants action)
  "Execute action when all participants arrive at rendezvous point.

  This is a higher-level abstraction over barriers where the action
  is executed exactly once when all participants arrive.

  Args:
    participants - List of swarm IDs
    action - Function to execute when all arrive (takes no arguments)

  Returns:
    Result of action function.

  Example:
    (rendezvous-point '(\"swarm-a\" \"swarm-b\")
                      (lambda ()
                        (format t \"Starting distributed transaction~%\")
                        (commit-distributed-txn)))

  See Also:
    MAKE-BARRIER, WITH-BARRIER"
  (let* ((barrier-id (format nil "rendezvous-~A" (get-universal-time)))
         (action-executed nil)
         (action-result nil)
         (barrier (make-barrier barrier-id
                               participants
                               :timeout 60
                               :callback (lambda (b)
                                          (declare (ignore b))
                                          (setf action-executed t
                                                action-result (funcall action))))))
    (barrier-wait barrier)
    (if action-executed
        action-result
        (error "Rendezvous failed: not all participants arrived"))))

;;;; ============================================================================
;;;; Timeout Handling with Restarts
;;;; ============================================================================

(define-condition barrier-timeout-error (sw4rm-orchestrator.errors:coordination-error)
  ((barrier-id
    :initarg :barrier-id
    :reader barrier-timeout-error-barrier-id
    :type string)
   (arrived
    :initarg :arrived
    :reader barrier-timeout-error-arrived
    :type list)
   (missing
    :initarg :missing
    :reader barrier-timeout-error-missing
    :type list))
  (:report (lambda (c s)
             (format s "Barrier ~S timed out. Arrived: ~{~A~^, ~}. Missing: ~{~A~^, ~}"
                     (barrier-timeout-error-barrier-id c)
                     (barrier-timeout-error-arrived c)
                     (barrier-timeout-error-missing c))))
  (:documentation "Condition signaled when barrier timeout occurs."))

(defun barrier-wait-with-restarts (barrier &key (timeout nil))
  "Wait for barrier with restart options for timeout handling.

  This variant provides restarts for sophisticated error handling:
    - RETRY-WAIT: Retry waiting with extended timeout
    - PROCEED-ANYWAY: Continue despite timeout
    - CANCEL-BARRIER: Cancel the barrier

  Args:
    barrier - DISTRIBUTED-BARRIER instance
    timeout - Optional timeout in seconds

  Returns:
    T if barrier completed successfully.

  Raises:
    BARRIER-TIMEOUT-ERROR if timeout occurs and no restart invoked

  Example:
    (handler-bind
        ((barrier-timeout-error
           (lambda (c)
             (format t \"Timeout, retrying...~%\")
             (invoke-restart 'retry-wait 120))))
      (barrier-wait-with-restarts barrier))

  See Also:
    BARRIER-WAIT, BARRIER-TIMEOUT-ERROR"
  (declare (type distributed-barrier barrier))

  (restart-case
      (multiple-value-bind (success arrivals)
          (barrier-wait barrier :timeout timeout)
        (unless success
          (let* ((arrived-ids (loop for id being the hash-keys of arrivals
                                    collect id))
                 (missing-ids (set-difference (barrier-participants barrier)
                                             arrived-ids
                                             :test #'string=)))
            (error 'barrier-timeout-error
                   :operation :barrier
                   :participants (barrier-participants barrier)
                   :barrier-id (barrier-id barrier)
                   :arrived arrived-ids
                   :missing missing-ids)))
        t)

    (retry-wait (&optional (new-timeout 60))
      :report "Retry waiting for barrier with extended timeout"
      :interactive (lambda () (list (read)))
      (barrier-wait-with-restarts barrier :timeout new-timeout))

    (proceed-anyway ()
      :report "Proceed despite barrier timeout"
      (format t "WARNING: Proceeding with incomplete barrier ~A~%"
              (barrier-id barrier))
      nil)

    (cancel-barrier ()
      :report "Cancel the barrier"
      (barrier-cancel barrier)
      nil)))

;;;; ============================================================================
;;;; Print Method
;;;; ============================================================================

(defmethod print-object ((barrier distributed-barrier) stream)
  "Print human-readable representation of DISTRIBUTED-BARRIER.

  Format: #<DISTRIBUTED-BARRIER id=\"sync-1\" state=:WAITING arrived=2/3>"
  (print-unreadable-object (barrier stream :type t)
    (bt:with-lock-held ((barrier-lock barrier))
      (format stream "id=~S state=~S arrived=~D/~D"
              (barrier-id barrier)
              (barrier-state barrier)
              (hash-table-count (barrier-arrived barrier))
              (length (barrier-participants barrier))))))

;;;; End of file
