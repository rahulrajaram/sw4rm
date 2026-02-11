;;;; ack-manager.lisp - ACK lifecycle manager for message tracking
;;;;
;;;; Manages acknowledgement lifecycle for outgoing and incoming messages,
;;;; providing stage tracking, timeout reconciliation, and record management.
;;;;
;;;; Ported from Python SDK's ACKLifecycleManager (sw4rm/ack_integration.py).
;;;; Implements ACK tracking per spec section 11 requirements.

(in-package #:sw4rm)

;;;; ACK Record Structure
;;;;
;;;; Each tracked message has an associated ack-record that captures its
;;;; current acknowledgement stage, direction, and metadata.

(defstruct (ack-record (:constructor %make-ack-record))
  "Record tracking the acknowledgement state of a single message.

Fields:
  MESSAGE-ID: Unique message identifier (UUIDv4 string).
  STAGE: Current ACK stage (integer from AckStage enum constants).
         Valid values: +ACK-STAGE-UNSPECIFIED+, +RECEIVED+, +READ+,
         +FULFILLED+, +REJECTED+, +FAILED+, +TIMED-OUT+.
  ERROR-CODE: Protocol error code (integer from ErrorCode enum constants).
              Defaults to +ERROR-CODE-UNSPECIFIED+.
  DIRECTION: Message direction, either :IN (incoming) or :OUT (outgoing).
  TIMESTAMP-MS: Unix timestamp in milliseconds when the record was created.
  NOTE: Optional human-readable annotation (e.g., rejection reason)."
  (message-id  ""                       :type string)
  (stage       +ack-stage-unspecified+  :type integer)
  (error-code  +error-code-unspecified+ :type integer)
  (direction   :out                     :type keyword)
  (timestamp-ms 0                       :type integer)
  (note        ""                       :type string))

(defun make-ack-record (&key message-id
                              (stage +ack-stage-unspecified+)
                              (error-code +error-code-unspecified+)
                              (direction :out)
                              timestamp-ms
                              (note ""))
  "Create a new ACK record with validated fields.

Args:
  MESSAGE-ID: Unique message identifier (required, string).
  STAGE: Initial ACK stage constant (default: +ACK-STAGE-UNSPECIFIED+).
  ERROR-CODE: Initial error code constant (default: +ERROR-CODE-UNSPECIFIED+).
  DIRECTION: Message direction, :IN or :OUT (default: :OUT).
  TIMESTAMP-MS: Unix timestamp in milliseconds (default: current time).
  NOTE: Optional annotation string (default: empty string).

Returns:
  New ACK-RECORD instance.

Signals:
  VALIDATION-ERROR: If MESSAGE-ID is nil or empty, or DIRECTION is invalid."
  (unless (and message-id (not (string= message-id "")))
    (error 'validation-error
           :message "message-id is required and must be non-empty"
           :field "message-id"
           :constraint "must be a non-empty string"))
  (unless (member direction '(:in :out))
    (error 'validation-error
           :message (format nil "direction must be :IN or :OUT, got ~S" direction)
           :field "direction"
           :constraint "must be :IN or :OUT"))
  (%make-ack-record
   :message-id message-id
   :stage stage
   :error-code error-code
   :direction direction
   :timestamp-ms (or timestamp-ms (current-time-ms))
   :note note))

;;;; Terminal Stage Predicate

(defun terminal-ack-stage-p (stage)
  "Check if an ACK stage is terminal (no further transitions expected).

Per spec section 11, terminal ACK stages are:
- FULFILLED: Message successfully processed.
- REJECTED: Message explicitly rejected.
- FAILED: Message processing failed.
- TIMED_OUT: Message exceeded timeout threshold.

Args:
  STAGE: ACK stage integer constant.

Returns:
  T if the stage is terminal, NIL otherwise.

Example:
  (terminal-ack-stage-p +fulfilled+) => T
  (terminal-ack-stage-p +received+)  => NIL"
  (member stage (list +fulfilled+ +rejected+ +failed+ +timed-out+)))

;;;; Time Utility

(defun current-time-ms ()
  "Return the current Unix time in milliseconds.

Returns:
  Integer representing Unix epoch milliseconds."
  ;; Common Lisp universal-time starts at 1900-01-01; offset to Unix epoch.
  (let ((unix-epoch-offset 2208988800))
    (* (- (get-universal-time) unix-epoch-offset) 1000)))

;;;; ACK Manager Class

(defclass ack-manager ()
  ((pending-acks
    :accessor ack-manager-pending-acks
    :type hash-table
    :initform (make-hash-table :test 'equal)
    :documentation "Hash table mapping message-id (string) to ack-record.
                    Contains all messages currently being tracked for ACK lifecycle.")

   (agent-id
    :initarg :agent-id
    :accessor ack-manager-agent-id
    :type string
    :documentation "Identifier of the agent owning this ACK manager.")

   (auto-ack-p
    :initarg :auto-ack-p
    :accessor ack-manager-auto-ack-p
    :type boolean
    :initform t
    :documentation "When T, automatically progress ACK stages on key events.
                    When NIL, callers must manually update ACK stages.")

   (ack-timeout-seconds
    :initarg :ack-timeout-seconds
    :accessor ack-manager-ack-timeout-seconds
    :type integer
    :initform 10
    :documentation "Timeout threshold in seconds for unacknowledged messages.
                    Per spec section 11, the default is 10 seconds.
                    Messages exceeding this threshold are considered stale
                    and eligible for reconciliation.")

   (lock
    :reader ack-manager-lock
    :initform (bordeaux-threads:make-lock "ack-manager-lock")
    :documentation "Lock for thread-safe access to pending-acks."))
  (:documentation "Manages ACK lifecycle tracking for outgoing and incoming messages.

Implements message-level acknowledgement tracking per SW4RM spec section 11.
Each message sent or received is registered as an ack-record with its current
stage, and can be updated as acknowledgements arrive or processing progresses.

The manager supports:
- Outgoing message tracking (awaiting remote ACK)
- Incoming message tracking (local processing status)
- Stage updates with error codes and notes
- Timeout-based stale record reconciliation
- Direction-filtered queries for unacked messages

Thread Safety:
  All mutating operations acquire an internal lock. Read operations on
  individual records are safe without locking, but iteration over the
  pending-acks table uses the lock for consistency.

Example:
  (let ((mgr (make-instance 'ack-manager :agent-id \"agent-1\")))
    (track-outgoing mgr \"msg-001\")
    (update-ack mgr \"msg-001\" +received+)
    (update-ack mgr \"msg-001\" +fulfilled+)
    (remove-ack mgr \"msg-001\"))"))

(defmethod initialize-instance :after ((mgr ack-manager) &key)
  "Validate ACK manager configuration after initialization."
  (with-slots (agent-id ack-timeout-seconds) mgr
    (unless (and (slot-boundp mgr 'agent-id)
                 (stringp agent-id)
                 (not (string= agent-id "")))
      (error 'validation-error
             :message "agent-id is required and must be a non-empty string"
             :field "agent-id"
             :constraint "must be a non-empty string"))
    (unless (and (integerp ack-timeout-seconds)
                 (> ack-timeout-seconds 0))
      (error 'validation-error
             :message (format nil "ack-timeout-seconds must be a positive integer, got ~S"
                              ack-timeout-seconds)
             :field "ack-timeout-seconds"
             :constraint "must be a positive integer"))))

(defmethod print-object ((mgr ack-manager) stream)
  "Print ACK manager in readable format."
  (print-unreadable-object (mgr stream :type t)
    (format stream "agent=~A pending=~D auto-ack=~A timeout=~Ds"
            (ack-manager-agent-id mgr)
            (hash-table-count (ack-manager-pending-acks mgr))
            (ack-manager-auto-ack-p mgr)
            (ack-manager-ack-timeout-seconds mgr))))

;;;; Generic Function Declarations
;;;;
;;;; Define the public protocol for ACK lifecycle management.

(defgeneric track-outgoing (manager message-id)
  (:documentation "Register an outgoing message for ACK tracking.

Creates a new ack-record with direction :OUT and stage +ACK-STAGE-UNSPECIFIED+.
The record is timestamped at creation time and added to the pending-acks table.

Args:
  MANAGER: ACK-MANAGER instance.
  MESSAGE-ID: Unique message identifier (string).

Returns:
  The newly created ACK-RECORD.

Signals:
  VALIDATION-ERROR: If MESSAGE-ID is nil, empty, or already tracked."))

(defgeneric track-incoming (manager message-id)
  (:documentation "Register an incoming message for ACK tracking.

Creates a new ack-record with direction :IN and stage +RECEIVED+.
Per spec section 11, incoming messages begin at RECEIVED stage since
they have already been delivered by the transport layer.

Args:
  MANAGER: ACK-MANAGER instance.
  MESSAGE-ID: Unique message identifier (string).

Returns:
  The newly created ACK-RECORD.

Signals:
  VALIDATION-ERROR: If MESSAGE-ID is nil, empty, or already tracked."))

(defgeneric update-ack (manager message-id stage &key error-code note)
  (:documentation "Update the ACK stage for a tracked message.

Transitions the ack-record to the given stage, optionally setting an
error code and annotation. Stage transitions are not validated against
a state machine; callers are responsible for logical stage ordering.

Args:
  MANAGER: ACK-MANAGER instance.
  MESSAGE-ID: Message identifier to update (string).
  STAGE: New ACK stage constant (e.g., +RECEIVED+, +FULFILLED+).
  ERROR-CODE: Optional protocol error code (default: unchanged).
  NOTE: Optional annotation string (default: unchanged).

Returns:
  The updated ACK-RECORD, or NIL if MESSAGE-ID is not tracked.

Signals:
  SW4RM-ERROR: If MESSAGE-ID is not found in pending-acks."))

(defgeneric get-unacked (manager &key direction)
  (:documentation "Get messages that have not yet reached a terminal ACK stage.

Returns ack-records whose stage is not terminal (i.e., not FULFILLED,
REJECTED, FAILED, or TIMED_OUT). Optionally filtered by direction.

Args:
  MANAGER: ACK-MANAGER instance.
  DIRECTION: Optional direction filter, :IN or :OUT.
             When NIL, returns unacked records in both directions.

Returns:
  List of ACK-RECORD structs."))

(defgeneric reconcile-stale (manager)
  (:documentation "Find messages that have exceeded the ACK timeout threshold.

Scans all pending (non-terminal) ack-records and returns those whose
age exceeds ACK-TIMEOUT-SECONDS. These records are candidates for
retry, escalation, or TIMED_OUT stage transition.

Per spec section 11, the default timeout is 10 seconds.

Args:
  MANAGER: ACK-MANAGER instance.

Returns:
  List of ACK-RECORD structs that are past the timeout threshold."))

(defgeneric remove-ack (manager message-id)
  (:documentation "Remove a completed ACK record from tracking.

Removes the ack-record for the given message-id from the pending-acks
table. Typically called after a message reaches a terminal stage and
has been processed or logged.

Args:
  MANAGER: ACK-MANAGER instance.
  MESSAGE-ID: Message identifier to remove (string).

Returns:
  The removed ACK-RECORD, or NIL if MESSAGE-ID was not tracked."))

;;;; Method Implementations

(defmethod track-outgoing ((mgr ack-manager) message-id)
  "Register an outgoing message for ACK tracking.

Creates a new ack-record with direction :OUT and stage +ACK-STAGE-UNSPECIFIED+,
then stores it in the pending-acks table keyed by message-id."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let ((table (ack-manager-pending-acks mgr)))
      (when (gethash message-id table)
        (error 'validation-error
               :message (format nil "message-id ~S is already being tracked" message-id)
               :field "message-id"
               :constraint "must not already be tracked"))
      (let ((record (make-ack-record :message-id message-id
                                     :stage +ack-stage-unspecified+
                                     :direction :out)))
        (setf (gethash message-id table) record)
        record))))

(defmethod track-incoming ((mgr ack-manager) message-id)
  "Register an incoming message for ACK tracking.

Creates a new ack-record with direction :IN and stage +RECEIVED+, since
the message has already been delivered by the transport layer."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let ((table (ack-manager-pending-acks mgr)))
      (when (gethash message-id table)
        (error 'validation-error
               :message (format nil "message-id ~S is already being tracked" message-id)
               :field "message-id"
               :constraint "must not already be tracked"))
      (let ((record (make-ack-record :message-id message-id
                                     :stage +received+
                                     :direction :in)))
        (setf (gethash message-id table) record)
        record))))

(defmethod update-ack ((mgr ack-manager) message-id stage
                       &key (error-code nil error-code-supplied-p)
                            (note nil note-supplied-p))
  "Update the ACK stage for a tracked message.

Locates the ack-record by message-id and updates its stage. If error-code
or note are supplied, those fields are also updated."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let* ((table (ack-manager-pending-acks mgr))
           (record (gethash message-id table)))
      (unless record
        (error 'sw4rm-error
               :message (format nil "message-id ~S is not tracked" message-id)
               :error-code +internal-error+))
      (setf (ack-record-stage record) stage)
      (when error-code-supplied-p
        (setf (ack-record-error-code record) error-code))
      (when note-supplied-p
        (setf (ack-record-note record) note))
      record)))

(defmethod get-unacked ((mgr ack-manager) &key (direction nil))
  "Get messages that have not yet reached a terminal ACK stage.

Iterates over all pending ack-records and collects those in non-terminal
stages. When DIRECTION is provided, further filters by :IN or :OUT."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let ((results nil))
      (maphash (lambda (id record)
                 (declare (ignore id))
                 (when (and (not (terminal-ack-stage-p (ack-record-stage record)))
                            (or (null direction)
                                (eq direction (ack-record-direction record))))
                   (push record results)))
               (ack-manager-pending-acks mgr))
      results)))

(defmethod reconcile-stale ((mgr ack-manager))
  "Find messages that have exceeded the ACK timeout threshold.

Computes the timeout threshold in milliseconds from ACK-TIMEOUT-SECONDS
and returns all non-terminal ack-records older than that threshold."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let* ((now (current-time-ms))
           (timeout-ms (* (ack-manager-ack-timeout-seconds mgr) 1000))
           (stale nil))
      (maphash (lambda (id record)
                 (declare (ignore id))
                 (when (and (not (terminal-ack-stage-p (ack-record-stage record)))
                            (> (- now (ack-record-timestamp-ms record)) timeout-ms))
                   (push record stale)))
               (ack-manager-pending-acks mgr))
      stale)))

(defmethod remove-ack ((mgr ack-manager) message-id)
  "Remove a completed ACK record from tracking.

Returns the removed ack-record, or NIL if the message-id was not tracked."
  (bordeaux-threads:with-lock-held ((ack-manager-lock mgr))
    (let* ((table (ack-manager-pending-acks mgr))
           (record (gethash message-id table)))
      (when record
        (remhash message-id table))
      record)))

;;;; Convenience Functions

(defun make-ack-manager (agent-id &key (auto-ack-p t) (ack-timeout-seconds 10))
  "Create a new ACK lifecycle manager.

Args:
  AGENT-ID: Identifier of the owning agent (string, required).
  AUTO-ACK-P: Enable automatic ACK progression (default: T).
  ACK-TIMEOUT-SECONDS: Timeout threshold in seconds (default: 10, per spec).

Returns:
  New ACK-MANAGER instance.

Example:
  (make-ack-manager \"agent-1\")
  (make-ack-manager \"agent-2\" :auto-ack-p nil :ack-timeout-seconds 30)"
  (make-instance 'ack-manager
                 :agent-id agent-id
                 :auto-ack-p auto-ack-p
                 :ack-timeout-seconds ack-timeout-seconds))

(defun ack-manager-count (manager)
  "Return the number of messages currently tracked by the ACK manager.

Args:
  MANAGER: ACK-MANAGER instance.

Returns:
  Non-negative integer."
  (hash-table-count (ack-manager-pending-acks manager)))

(defun ack-manager-get (manager message-id)
  "Look up an ack-record by message-id without removing it.

Args:
  MANAGER: ACK-MANAGER instance.
  MESSAGE-ID: Message identifier to look up (string).

Returns:
  ACK-RECORD if found, NIL otherwise."
  (gethash message-id (ack-manager-pending-acks manager)))
