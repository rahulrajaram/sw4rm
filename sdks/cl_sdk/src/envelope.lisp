;;;; envelope.lisp - Envelope construction and manipulation

(in-package #:sw4rm-sdk)

;;;; Three-ID Envelope Model (spec §11.3)
;;;
;;; The SW4RM protocol uses three distinct identifiers to track messages:
;;;
;;; 1. message_id (Required, UUIDv4):
;;;    - Unique per delivery attempt
;;;    - New UUID generated on each retry
;;;    - Used for acknowledgement targeting
;;;
;;; 2. correlation_id (Required, UUIDv4):
;;;    - Groups related operations in workflow/session
;;;    - Stable across entire flow
;;;    - Set to workflow_id or negotiation_id for correlation
;;;
;;; 3. idempotency_token (Optional):
;;;    - Enables exactly-once semantics
;;;    - Stable across retries of same logical operation
;;;    - Format: {producer_id}:{operation_type}:{deterministic_hash}

;;;; UUID Generation

(defun generate-uuid ()
  "Generate a new UUIDv4 string.

Returns:
  String representation of UUID (e.g., '550e8400-e29b-41d4-a716-446655440000')"
  (string-downcase (princ-to-string (uuid:make-v4-uuid))))

;;;; Hybrid Logical Clock (HLC) Stub
;;;
;;; Implementations MAY enable HLC timestamping per spec §4.
;;; This is a placeholder using Unix milliseconds.

(defun generate-hlc-timestamp ()
  "Generate HLC timestamp in canonical format HLC:<wall>:<logical>:<node>.

Per spec §4, HLC format combines physical time (Unix microseconds),
logical counter (always 0 in this stub), and node identifier (hostname).
Full HLC implementations should increment the logical counter on
concurrent events within the same microsecond.

Returns:
  String in format HLC:<unix_microseconds>:0:<hostname>."
  (format nil "HLC:~D:0:~A"
          (truncate (* (get-universal-time) 1000000))
          (machine-instance)))

;;;; Deterministic Hash Computation
;;;
;;; For idempotency token generation per spec §11.2.

(defun compute-deterministic-hash (params-plist)
  "Compute deterministic SHA256 hash from canonical operation parameters.

Args:
  PARAMS-PLIST: Property list of parameters that uniquely identify the operation.
                Should include all fields that distinguish this operation from others.

Returns:
  Hexadecimal string (first 16 characters of SHA256 hash).

Example:
  (compute-deterministic-hash '(:tool \"git-commit\" :repo \"myrepo\" :files (\"a.lisp\")))
  => \"a3b2c1d4e5f6a7b8\""
  ;; Canonicalize: sort keys and create stable representation
  (let* ((sorted-params (sort (copy-list params-plist)
                              #'string<
                              :key (lambda (x) (string (if (keywordp x) x "")))))
         (canonical-string (format nil "~{~A~^:~}" sorted-params))
         (digest (ironclad:digest-sequence :sha256
                                           (ironclad:ascii-string-to-byte-array
                                            canonical-string))))
    (subseq (ironclad:byte-array-to-hex-string digest) 0 16)))

(defun make-idempotency-token (producer-id operation-type deterministic-hash)
  "Create idempotency token in format: {producer_id}:{operation_type}:{deterministic_hash}.

Per spec §11.2, idempotency tokens SHOULD follow this format for consistency.

Args:
  PRODUCER-ID: ID of the agent/service producing the message
  OPERATION-TYPE: Type of operation (e.g., 'tool-call', 'task-submit')
  DETERMINISTIC-HASH: Hash computed from canonical operation parameters

Returns:
  Formatted idempotency token string.

Example:
  (make-idempotency-token \"agent-1\" \"git-commit\" \"abc123\")
  => \"agent-1:git-commit:abc123\""
  (format nil "~A:~A:~A" producer-id operation-type deterministic-hash))

;;;; Sequence Tracking
;;;
;;; Thread-safe sequence number generator for message ordering.

(defclass sequence-tracker ()
  ((current-sequence
    :initform 0
    :accessor sequence-tracker-current
    :documentation "Current sequence number.")
   (lock
    :initform (bordeaux-threads:make-lock "sequence-tracker-lock")
    :reader sequence-tracker-lock
    :documentation "Lock for thread-safe increment."))
  (:documentation "Thread-safe sequence number generator.

Maintains monotonic sequence numbers for message ordering.
Thread-safe for use across multiple agent threads."))

(defun make-sequence-tracker (&key (start 1))
  "Create a new sequence tracker starting at START (default 1).

Args:
  START: Initial sequence number (default 1)

Returns:
  New SEQUENCE-TRACKER instance."
  (let ((tracker (make-instance 'sequence-tracker)))
    (setf (sequence-tracker-current tracker) (1- start))
    tracker))

(defun next-sequence (tracker)
  "Get next sequence number from TRACKER in thread-safe manner.

Args:
  TRACKER: SEQUENCE-TRACKER instance

Returns:
  Next sequence number (integer)."
  (bordeaux-threads:with-lock-held ((sequence-tracker-lock tracker))
    (incf (sequence-tracker-current tracker))))

;;;; Envelope Construction
;;;
;;; Build message envelopes with Three-ID model support.

(defun make-envelope (&key
                      producer-id
                      message-type
                      (content-type "application/json")
                      (payload #())
                      correlation-id
                      idempotency-token
                      sequence-number
                      (retry-count 0)
                      repo-id
                      worktree-id
                      ttl-ms
                      (state +sent+)
                      effective-policy-id
                      audit-proof
                      audit-policy-id)
  "Build a message envelope with Three-ID model support (spec §11.3).

Args:
  PRODUCER-ID: ID of the producing agent/service (required)
  MESSAGE-TYPE: Type of message from constants (required, e.g., +DATA+)
  CONTENT-TYPE: MIME type of payload (default: 'application/json')
  PAYLOAD: Message payload as byte array (default: empty)
  CORRELATION-ID: Workflow/session identifier (auto-generated if nil)
  IDEMPOTENCY-TOKEN: Stable token for deduplication (optional)
  SEQUENCE-NUMBER: Sequence number for ordering (default: 1)
  RETRY-COUNT: Number of retry attempts (default: 0)
  REPO-ID: Repository identifier (optional)
  WORKTREE-ID: Worktree identifier (optional)
  TTL-MS: Time-to-live in milliseconds (default: 0 = no expiry)
  STATE: Initial envelope state (default: +SENT+)
  EFFECTIVE-POLICY-ID: ID of effective policy governing this operation
  AUDIT-PROOF: Cryptographic proof for audit trail (bytes)
  AUDIT-POLICY-ID: ID of audit policy governing this envelope

Returns:
  Property list compatible with sw4rm.common.Envelope protobuf message.

Note:
  - MESSAGE-ID is always auto-generated (new UUID per attempt)
  - CORRELATION-ID is auto-generated if not provided
  - For retry scenarios: keep CORRELATION-ID and IDEMPOTENCY-TOKEN,
    but increment RETRY-COUNT and let MESSAGE-ID regenerate

Example:
  (make-envelope :producer-id \"agent-1\"
                 :message-type +DATA+
                 :payload (babel:string-to-octets \"{\\\"task\\\":\\\"test\\\"}\"))"
  (unless producer-id
    (error 'validation-error
           :message "producer-id is required"
           :field "producer-id"
           :constraint "must not be nil"))
  (unless message-type
    (error 'validation-error
           :message "message-type is required"
           :field "message-type"
           :constraint "must not be nil"))

  (list :message-id (generate-uuid)
        :idempotency-token (or idempotency-token "")
        :producer-id producer-id
        :correlation-id (or correlation-id (generate-uuid))
        :sequence-number (or sequence-number 1)
        :retry-count retry-count
        :message-type message-type
        :content-type content-type
        :content-length (length payload)
        :repo-id (or repo-id "")
        :worktree-id (or worktree-id "")
        :hlc-timestamp (generate-hlc-timestamp)
        :ttl-ms (or ttl-ms 0)
        :state state
        :effective-policy-id (or effective-policy-id "")
        :payload payload
        :audit-proof (or audit-proof #())
        :audit-policy-id (or audit-policy-id "")))

;;;; Envelope State Management
;;;
;;; Functions for envelope lifecycle management per spec §11.

(defun update-envelope-state (envelope new-state)
  "Update the state of an envelope.

Args:
  ENVELOPE: Envelope property list
  NEW-STATE: New state value (from constants, e.g., +FULFILLED-ENVELOPE+)

Returns:
  Updated envelope (same object, modified in place).

Example:
  (let ((env (make-envelope :producer-id \"agent-1\" :message-type +DATA+)))
    (update-envelope-state env +received-envelope+)
    (getf env :state)) => 2"
  (setf (getf envelope :state) new-state)
  envelope)

(defun terminal-state-p (state)
  "Check if an envelope state is terminal (no further transitions expected).

Per spec §11, terminal states are:
- FULFILLED (+fulfilled-envelope+)
- REJECTED (+rejected-envelope+)
- FAILED (+failed-envelope+)
- TIMED_OUT (+timed-out-envelope+)

Args:
  STATE: Envelope state value (integer from constants)

Returns:
  T if state is terminal, NIL otherwise.

Example:
  (terminal-state-p +fulfilled-envelope+) => T
  (terminal-state-p +received-envelope+) => NIL"
  (member state (list +fulfilled-envelope+
                      +rejected-envelope+
                      +failed-envelope+
                      +timed-out-envelope+)))

;;;; Envelope Validation
;;;
;;; Validate envelope structure and constraints.

(defun validate-envelope (envelope)
  "Validate envelope structure and required fields.

Args:
  ENVELOPE: Envelope property list

Signals:
  VALIDATION-ERROR if validation fails

Returns:
  T if valid, signals error otherwise."
  (macrolet ((check-field (field constraint &optional (error-msg nil))
               `(unless ,constraint
                  (error 'validation-error
                         :message (or ,error-msg
                                      (format nil "~A validation failed" ',field))
                         :field (string-downcase (symbol-name ',field))
                         :constraint (format nil "~A" ',constraint)))))
    (check-field message-id (getf envelope :message-id))
    (check-field producer-id (getf envelope :producer-id))
    (check-field correlation-id (getf envelope :correlation-id))
    (check-field message-type (getf envelope :message-type))
    (check-field sequence-number
                 (and (integerp (getf envelope :sequence-number))
                      (> (getf envelope :sequence-number) 0))
                 "sequence-number must be positive integer")
    (check-field retry-count
                 (and (integerp (getf envelope :retry-count))
                      (>= (getf envelope :retry-count) 0))
                 "retry-count must be non-negative integer"))
  t)
