;;;; audit.lisp
;;;; Audit proof and verification support for SW4RM protocol

(in-package :sw4rm-sdk)

;;; Audit Data Structures

(defstruct audit-proof
  "Cryptographic proof for audit verification."
  (proof-id nil :type (or null string))
  (proof-type nil :type (or null keyword))
  (proof-data nil :type t)
  (created-at (get-universal-time) :type integer)
  (verified nil :type boolean))

(defstruct audit-policy
  "Policy governing audit requirements."
  (policy-id nil :type (or null string))
  (require-proof nil :type boolean)
  (verification-level nil :type (or null keyword))
  (retention-days nil :type (or null integer)))

(defstruct audit-record
  "Record of an auditable action."
  (record-id nil :type (or null string))
  (envelope-id nil :type (or null string))
  (action nil :type (or null keyword))
  (actor-id nil :type (or null string))
  (timestamp (get-universal-time) :type integer)
  (proof nil :type (or null audit-proof))
  (metadata nil :type list))

;;; Auditor Protocol

(defgeneric create-proof (auditor envelope policy)
  (:documentation "Create an audit proof for an envelope.

   Args:
     auditor: Auditor instance
     envelope: Envelope to create proof for
     policy: Audit policy to apply

   Returns:
     audit-proof struct"))

(defgeneric verify-proof (auditor proof envelope)
  (:documentation "Verify an audit proof against an envelope.

   Args:
     auditor: Auditor instance
     proof: audit-proof struct
     envelope: Envelope to verify against

   Returns:
     T if proof is valid, NIL otherwise"))

(defgeneric record-audit (auditor record)
  (:documentation "Record an audit event.

   Args:
     auditor: Auditor instance
     record: audit-record struct

   Returns:
     The record-id"))

(defgeneric query-records (auditor &key envelope-id action actor-id from-time to-time limit)
  (:documentation "Query audit records.

   Args:
     auditor: Auditor instance
     envelope-id: Filter by envelope ID
     action: Filter by action keyword
     actor-id: Filter by actor ID
     from-time: Filter by minimum timestamp
     to-time: Filter by maximum timestamp
     limit: Maximum number of records to return

   Returns:
     List of audit-record structs"))

;;; No-Op Auditor (for testing/development)

(defclass no-op-auditor ()
  ()
  (:documentation "Auditor that does nothing. Useful for testing."))

(defmethod create-proof ((auditor no-op-auditor) envelope policy)
  "Create a no-op proof."
  (declare (ignore envelope policy))
  (make-audit-proof
   :proof-id (format nil "noop-~A" (get-universal-time))
   :proof-type :no-op
   :proof-data nil
   :created-at (get-universal-time)
   :verified t))

(defmethod verify-proof ((auditor no-op-auditor) proof envelope)
  "Always returns T for no-op proofs."
  (declare (ignore proof envelope))
  t)

(defmethod record-audit ((auditor no-op-auditor) record)
  "Does not record anything."
  (declare (ignore record))
  nil)

(defmethod query-records ((auditor no-op-auditor) &key envelope-id action actor-id from-time to-time limit)
  "Always returns empty list."
  (declare (ignore envelope-id action actor-id from-time to-time limit))
  nil)

;;; In-Memory Auditor

(defclass in-memory-auditor ()
  ((records
    :initarg :records
    :accessor audit-records
    :type list
    :initform nil
    :documentation "List of audit records, newest first.")

   (max-records
    :initarg :max-records
    :accessor max-records
    :type (integer 0 *)
    :initform 10000
    :documentation "Maximum number of records to retain.")

   (lock
    :accessor auditor-lock
    :initform (bt:make-lock "auditor-lock")
    :documentation "Lock for thread-safe operations."))
  (:documentation "In-memory auditor for development and testing.
                   Records are kept in memory and pruned when max-records is exceeded."))

(defmethod create-proof ((auditor in-memory-auditor) envelope policy)
  "Create a simple hash-based proof."
  (declare (ignore policy))
  (let* ((envelope-hash (compute-envelope-hash envelope))
         (proof-id (format nil "proof-~A-~A"
                          (get-universal-time)
                          (random 1000000))))
    (make-audit-proof
     :proof-id proof-id
     :proof-type :sha256-hash
     :proof-data envelope-hash
     :created-at (get-universal-time)
     :verified nil)))

(defmethod verify-proof ((auditor in-memory-auditor) proof envelope)
  "Verify a hash-based proof."
  (when (eq (audit-proof-proof-type proof) :sha256-hash)
    (let ((expected-hash (audit-proof-proof-data proof))
          (actual-hash (compute-envelope-hash envelope)))
      (equal expected-hash actual-hash))))

(defmethod record-audit ((auditor in-memory-auditor) record)
  "Record an audit event in memory."
  (bt:with-lock-held ((auditor-lock auditor))
    (push record (audit-records auditor))

    ;; Prune if needed
    (when (> (length (audit-records auditor)) (max-records auditor))
      (setf (audit-records auditor)
            (subseq (audit-records auditor) 0 (max-records auditor))))

    (audit-record-record-id record)))

(defmethod query-records ((auditor in-memory-auditor)
                         &key envelope-id action actor-id from-time to-time limit)
  "Query audit records from memory."
  (let ((results (audit-records auditor)))

    ;; Apply filters
    (when envelope-id
      (setf results (remove-if-not
                     (lambda (r) (equal (audit-record-envelope-id r) envelope-id))
                     results)))

    (when action
      (setf results (remove-if-not
                     (lambda (r) (eq (audit-record-action r) action))
                     results)))

    (when actor-id
      (setf results (remove-if-not
                     (lambda (r) (equal (audit-record-actor-id r) actor-id))
                     results)))

    (when from-time
      (setf results (remove-if-not
                     (lambda (r) (>= (audit-record-timestamp r) from-time))
                     results)))

    (when to-time
      (setf results (remove-if-not
                     (lambda (r) (<= (audit-record-timestamp r) to-time))
                     results)))

    ;; Apply limit
    (if limit
        (subseq results 0 (min limit (length results)))
        results)))

(defgeneric clear-records (backend &key namespace)
  (:documentation "Clear stored records, optionally filtered by namespace."))

(defmethod clear-records ((auditor in-memory-auditor) &key &allow-other-keys)
  "Clear all audit records.

   Args:
     auditor: In-memory auditor instance"
  (bt:with-lock-held ((auditor-lock auditor))
    (setf (audit-records auditor) nil)))

;;; Utility Functions

(defun compute-envelope-hash (envelope)
  "Compute SHA-256 hash of an envelope.

   Args:
     envelope: Envelope data structure (hash table or plist)

   Returns:
     String hex representation of hash"
  (let* ((envelope-string (format nil "~S" envelope))
         (digest (ironclad:digest-sequence
                  :sha256
                  (ironclad:ascii-string-to-byte-array envelope-string))))
    (ironclad:byte-array-to-hex-string digest)))

(defun create-simple-proof (envelope &key (proof-type :sha256-hash))
  "Create a simple hash-based proof for an envelope.

   Args:
     envelope: Envelope data structure
     proof-type: Type of proof to create (default :sha256-hash)

   Returns:
     audit-proof struct"
  (let ((proof-id (format nil "proof-~A-~A"
                         (get-universal-time)
                         (random 1000000))))
    (case proof-type
      (:sha256-hash
       (make-audit-proof
        :proof-id proof-id
        :proof-type :sha256-hash
        :proof-data (compute-envelope-hash envelope)
        :created-at (get-universal-time)
        :verified nil))
      (t
       (error "Unsupported proof type: ~A" proof-type)))))

(defun verify-audit-proof (proof envelope)
  "Verify an audit proof against an envelope.

   Args:
     proof: audit-proof struct
     envelope: Envelope data structure

   Returns:
     T if proof is valid, NIL otherwise"
  (case (audit-proof-proof-type proof)
    (:sha256-hash
     (let ((expected-hash (audit-proof-proof-data proof))
           (actual-hash (compute-envelope-hash envelope)))
       (equal expected-hash actual-hash)))
    (:no-op
     t)
    (t
     nil)))

(defun create-audit-record (&key record-id envelope-id action actor-id proof metadata)
  "Create an audit record.

   Args:
     record-id: Unique record identifier
     envelope-id: Associated envelope ID
     action: Action keyword (:send, :receive, :process, etc.)
     actor-id: ID of the actor performing the action
     proof: Optional audit-proof struct
     metadata: Optional metadata plist

   Returns:
     audit-record struct"
  (make-audit-record
   :record-id (or record-id
                 (format nil "record-~A-~A"
                        (get-universal-time)
                        (random 1000000)))
   :envelope-id envelope-id
   :action action
   :actor-id actor-id
   :timestamp (get-universal-time)
   :proof proof
   :metadata metadata))

(defun audit-record-to-plist (record)
  "Convert an audit record to a property list.

   Args:
     record: audit-record struct

   Returns:
     Property list"
  (list :record-id (audit-record-record-id record)
        :envelope-id (audit-record-envelope-id record)
        :action (audit-record-action record)
        :actor-id (audit-record-actor-id record)
        :timestamp (audit-record-timestamp record)
        :proof (when (audit-record-proof record)
                 (list :proof-id (audit-proof-proof-id (audit-record-proof record))
                       :proof-type (audit-proof-proof-type (audit-record-proof record))
                       :verified (audit-proof-verified (audit-record-proof record))))
        :metadata (audit-record-metadata record)))

(defun make-default-audit-policy (&key (require-proof t)
                                      (verification-level :basic)
                                      (retention-days 90))
  "Create a default audit policy.

   Args:
     require-proof: Whether proofs are required (default T)
     verification-level: Level of verification (:none, :basic, :strict)
     retention-days: Number of days to retain records (default 90)

   Returns:
     audit-policy struct"
  (make-audit-policy
   :policy-id (format nil "policy-~A" (get-universal-time))
   :require-proof require-proof
   :verification-level verification-level
   :retention-days retention-days))
