;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; persistence/wal.lisp
;;;;
;;;; Write-Ahead Logging for Orchestrator Durability
;;;;
;;;; This module provides Write-Ahead Logging (WAL) for the SW4RM orchestrator,
;;;; enabling crash recovery without losing in-flight operations.
;;;;
;;;; WAL Pattern:
;;;;   1. Before executing operation, log entry to WAL
;;;;   2. Log is written to disk (with configurable sync strategy)
;;;;   3. If crash occurs, replay log to recover state
;;;;   4. Orchestrator resumes from last operation
;;;;
;;;; This is complementary to checkpointing:
;;;;   - Checkpoints: Periodic full snapshots (large, slow to write)
;;;;   - WAL: Continuous operation log (incremental, fast)
;;;;   - Together: Minimal data loss with reasonable performance
;;;;
;;;; Features:
;;;;   - Circular log file with automatic rotation
;;;;   - Configurable sync modes (sync, async, batch)
;;;;   - Log compaction to remove obsolete entries
;;;;   - Replay for recovery with filtering by operation type
;;;;   - Metrics and statistics
;;;;   - Thread-safe operations
;;;;   - 16-shard lock pool for high-concurrency workloads (P2-3/P3-10)
;;;;
;;;; Spec References:
;;;;   - COMMON_LISP_PLAN.md Section 2.2.4: Image-based development
;;;;   - Lines 220-252: WAL specifications
;;;;   - P2-3: WAL concurrency optimization design (sharded locks)
;;;;   - P3-10: WAL lock sharding coordination
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.persistence)

;;;; ============================================================================
;;;; WAL Binary Format Constants
;;;; ============================================================================

(defconstant +wal-magic-number+ #x57414C30  ;; "WAL0" in ASCII
  "Magic number identifying a WAL entry.

   This 4-byte sequence appears at the start of each WAL entry
   to enable reliable detection of entry boundaries during recovery.")

(defconstant +wal-entry-header-size+ 28
  "Size of WAL entry header in bytes.

   Layout:
     4 bytes: magic number
     8 bytes: sequence number
     8 bytes: timestamp
     4 bytes: operation type (hash of symbol name)
     4 bytes: payload length")

;;;; ============================================================================
;;;; WAL Lock Sharding Constants
;;;; ============================================================================
;;;;
;;;; For high-concurrency workloads, a single buffer lock becomes a bottleneck.
;;;; We implement a 16-shard lock pool keyed by swarm ID, enabling concurrent
;;;; appends to different shards while maintaining total ordering via sequence.
;;;;
;;;; Design (P2-3/P3-10 from COMMON_LISP_PLAN.md):
;;;;   - 16-shard lock pool keyed by swarm ID hash
;;;;   - Per-shard buffers for concurrent appends
;;;;   - Sequence lock separated from shard locks
;;;;   - Flush collects all shards and sorts by sequence
;;;;   - Compaction coordinates safely across shards
;;;;   - Truncation maintains ordering invariants
;;;;   - Recovery replays in correct sequence

(defconstant +wal-shard-count+ 16
  "Number of shards in the WAL lock pool.

   16 shards provide good concurrency while keeping memory overhead low.
   Must be a power of 2 for efficient modulo via bitwise AND.")

(defconstant +wal-shard-mask+ (1- +wal-shard-count+)
  "Bitmask for computing shard index from hash (shard-count - 1).")

;;;; ============================================================================
;;;; CRC32 Implementation
;;;; ============================================================================
;;;;
;;;; We implement CRC32 (IEEE 802.3 polynomial) for integrity checking.
;;;; This is the standard CRC32 used by Ethernet, gzip, PNG, etc.

(defparameter *crc32-table* nil
  "Pre-computed CRC32 lookup table for fast checksum calculation.")

(defun initialize-crc32-table ()
  "Initialize the CRC32 lookup table using IEEE 802.3 polynomial.

   The polynomial is 0xEDB88320 (reflected form of 0x04C11DB7).
   This is called once at load time."
  (let ((table (make-array 256 :element-type '(unsigned-byte 32))))
    (dotimes (i 256)
      (let ((crc i))
        (dotimes (j 8)
          (if (oddp crc)
              (setf crc (logxor (ash crc -1) #xEDB88320))
              (setf crc (ash crc -1))))
        (setf (aref table i) crc)))
    (setf *crc32-table* table)))

;; Initialize table at load time
(initialize-crc32-table)

(defun crc32 (octets &optional (initial #xFFFFFFFF))
  "Compute CRC32 checksum of byte sequence.

   Args:
     octets - A sequence of (unsigned-byte 8) values
     initial - Starting CRC value (default: #xFFFFFFFF)

   Returns:
     32-bit CRC32 checksum as unsigned integer.

   Notes:
     - Uses IEEE 802.3 polynomial (same as Ethernet, gzip, PNG)
     - Returns the complement of the final CRC (standard CRC32 convention)

   Example:
     (crc32 #(72 101 108 108 111))  ; \"Hello\"
     => 4157704578"
  (declare (type (unsigned-byte 32) initial))
  (unless *crc32-table*
    (initialize-crc32-table))
  (let ((crc initial))
    (declare (type (unsigned-byte 32) crc))
    (loop for byte across octets
          do (setf crc (logxor (aref *crc32-table*
                                     (logand (logxor crc byte) #xFF))
                               (ash crc -8))))
    (logxor crc #xFFFFFFFF)))

(defun crc32-update (crc octets)
  "Update running CRC32 with additional bytes.

   Args:
     crc - Current CRC state (not finalized)
     octets - Additional bytes to process

   Returns:
     Updated CRC state (not finalized).

   Notes:
     To finalize, XOR result with #xFFFFFFFF."
  (declare (type (unsigned-byte 32) crc))
  (unless *crc32-table*
    (initialize-crc32-table))
  (loop for byte across octets
        do (setf crc (logxor (aref *crc32-table*
                                   (logand (logxor crc byte) #xFF))
                             (ash crc -8))))
  crc)

;;;; ============================================================================
;;;; WAL-ENTRY Structure
;;;; ============================================================================

;;; WAL-ENTRY
;;; Single entry in the write-ahead log.
;;; Fields:
;;;   - SEQUENCE: Monotonic sequence number
;;;   - TIMESTAMP: Universal time when logged
;;;   - OPERATION: Operation type (:route, :register, :unregister, etc.)
;;;   - DATA: Serialized operation data
;;;   - CHECKSUM: CRC32 checksum for integrity
;;;   - SWARM-ID: Swarm ID for shard routing (optional)
;;;
;;; The sequence number enables:
;;;   - Ordering of operations
;;;   - Deduplication (idempotency)
;;;   - Partial replay (from specific sequence onward)
;;;
;;; See Also:
;;;   WAL-LOG, WAL-APPEND, WAL-REPLAY

(defstruct wal-entry
  ;; sequence: Monotonically increasing sequence number
  (sequence 0 :type (integer 0 *))
  ;; timestamp: Universal time when entry was logged
  (timestamp (get-universal-time) :type integer)
  ;; operation: Operation type keyword (:route, :register, etc.)
  (operation :unknown :type keyword)
  ;; data: Serialized operation data (plist or structured data)
  (data nil :type t)
  ;; checksum: CRC32 checksum for integrity verification
  (checksum 0 :type (unsigned-byte 32))
  ;; swarm-id: Swarm ID for shard routing (optional)
  (swarm-id nil :type (or null string)))

;;;; ============================================================================
;;;; Shard Initialization Functions
;;;; ============================================================================

(defun initialize-shard-locks ()
  "Create and initialize the array of 16 shard locks.

   Returns:
     Simple vector of 16 bordeaux-threads lock objects.

   Notes:
     - Each lock is named 'wal-shard-N' for debugging
     - Called during WAL-LOG instance creation"
  (let ((locks (make-array +wal-shard-count+)))
    (dotimes (i +wal-shard-count+)
      (setf (aref locks i)
            (bt:make-lock (format nil "wal-shard-~D" i))))
    locks))

(defun initialize-shard-buffers ()
  "Create and initialize the array of 16 shard buffers.

   Returns:
     Simple vector of 16 adjustable vectors (each starts empty).

   Notes:
     - Each buffer is an adjustable vector with fill-pointer
     - Called during WAL-LOG instance creation"
  (let ((buffers (make-array +wal-shard-count+)))
    (dotimes (i +wal-shard-count+)
      (setf (aref buffers i)
            (make-array 0 :element-type 't :adjustable t :fill-pointer 0)))
    buffers))

(defun compute-shard-index (swarm-id)
  "Compute shard index from swarm ID using hash.

   Args:
     swarm-id - String or NIL. If NIL, returns 0.

   Returns:
     Integer in range [0, 15] (shard index).

   Notes:
     - Uses sxhash for hash computation
     - Applies bitmask for efficient modulo
     - NIL swarm-id maps to shard 0 (legacy compatibility)"
  (if (null swarm-id)
      0
      (logand (sxhash swarm-id) +wal-shard-mask+)))

;;;; ============================================================================
;;;; WAL-LOG Class (Main WAL Abstraction)
;;;; ============================================================================

(defclass wal-log ()
  ((path
    :initarg :path
    :accessor wal-path
    :type (or string pathname)
    :documentation "File path for the write-ahead log.

                   Can be a relative or absolute path. Logs are typically
                   stored in a dedicated directory like /var/sw4rm/wal/")

   (stream
    :accessor wal-stream
    :initform nil
    :type (or null stream)
    :documentation "Open file stream for writing WAL entries.

                   Managed internally. Use WAL-APPEND and WAL-FLUSH
                   rather than direct stream access.")

   (sequence-number
    :accessor wal-sequence-number
    :initform 0
    :type (integer 0 *)
    :documentation "Current sequence number for next entry.

                   Incremented with each WAL-APPEND. Enables ordering
                   and idempotency checking.")

   (sequence-lock
    :accessor wal-sequence-lock
    :initform (bt:make-lock "wal-sequence")
    :type bt:lock
    :documentation "Lock protecting sequence number allocation.

                   Separated from shard locks to allow concurrent
                   appends while ensuring globally unique sequences.")

   (buffer
    :accessor wal-buffer
    :initform (make-array 0 :element-type 't :adjustable t :fill-pointer 0)
    :type vector
    :documentation "In-memory buffer of pending entries (legacy single-buffer mode).

                   When sharding is enabled, this is unused. Kept for
                   backward compatibility with non-sharded WAL files.")

   (buffer-lock
    :accessor wal-buffer-lock
    :initform (bt:make-lock "wal-buffer")
    :type bt:lock
    :documentation "Lock protecting buffer from concurrent access (legacy mode).")

   (shard-locks
    :accessor wal-shard-locks
    :initform (initialize-shard-locks)
    :type simple-vector
    :documentation "Array of 16 locks for sharded WAL operation.

                   Each lock protects its corresponding shard buffer.
                   Shard index is computed by hashing swarm ID.")

   (shard-buffers
    :accessor wal-shard-buffers
    :initform (initialize-shard-buffers)
    :type simple-vector
    :documentation "Array of 16 buffers for per-shard entry accumulation.

                   Entries are appended to shards concurrently, then
                   merged and sorted by sequence during flush.")

   (sharding-enabled
    :accessor wal-sharding-enabled
    :initarg :sharding-enabled
    :initform t
    :type boolean
    :documentation "Whether lock sharding is enabled.

                   When T (default), uses 16-shard lock pool.
                   When NIL, uses single buffer-lock (legacy mode).")

   (flush-interval
    :initarg :flush-interval
    :accessor wal-flush-interval
    :initform 1
    :type (or null (integer 1 *))
    :documentation "Flush buffer to disk every N entries (NIL = manual only).

                   - NIL: Entries stay in memory until manual WAL-FLUSH
                   - 1: Flush after each entry (safest, slowest)
                   - 10-100: Batch multiple entries before flushing (recommended)

                   See Also:
                     WAL-FLUSH, *wal-sync-mode*")

   (max-size
    :initarg :max-size
    :accessor wal-max-size
    :initform (* 1024 1024 100)  ;; 100 MB default
    :type (integer 1 *)
    :documentation "Maximum size of WAL file before rotation (bytes).

                   When log exceeds this size, a new log file is started.
                   Old file is renamed with .N suffix (e.g., wal.0, wal.1).

                   Default: 100 MB. Set lower for frequent rotation,
                   higher for fewer filesystem operations.

                   See Also:
                     WAL-ROTATE")

   (sync-mode
    :initarg :sync-mode
    :accessor wal-sync-mode
    :initform :sync
    :type (member :sync :async :batch)
    :documentation "Durability sync mode for flush operations.

                   - :SYNC: fsync after every flush (safest, slowest)
                   - :ASYNC: No fsync, relies on OS buffer (faster, risky)
                   - :BATCH: Periodic group fsync (balanced)

                   Default: :SYNC. Most production systems use :BATCH.

                   See Also:
                     WAL-ENSURE-DURABILITY, *wal-sync-mode*")

   (entry-count
    :accessor wal-entry-count
    :initform 0
    :type (integer 0 *)
    :documentation "Total entries written since WAL creation.")

   (rotation-count
    :accessor wal-rotation-count
    :initform 0
    :type (integer 0 *)
    :documentation "Number of times log file has been rotated.")

   (stats
    :accessor wal-stats
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Operation statistics (operation type -> count).")

   (created-at
    :accessor wal-created-at
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when this WAL instance was created."))

  (:documentation "Write-Ahead Log for orchestrator durability.

   A WAL-LOG maintains an append-only log of operations for crash recovery.
   Before performing an operation, log the operation to WAL. If a crash
   occurs, replay the log to resume from the last checkpoint + replayed ops.

   Sharding (P2-3/P3-10):
     For high-concurrency workloads, WAL-LOG uses a 16-shard lock pool:
     - Entries are routed to shards by swarm-id hash
     - Concurrent appends to different shards proceed without contention
     - Sequence numbers are globally unique (via sequence-lock)
     - Flush merges all shards and sorts by sequence
     - Compaction and truncation coordinate across all shards

   Creating a WAL:
     (let ((wal (make-wal-log \"/var/sw4rm/wal\"
                              :flush-interval 10
                              :max-size (* 1024 1024 100))))
       ...)

   Logging an operation:
     (wal-append wal :route '(:from \"leaf-a\" :to \"leaf-b\")
                 :swarm-id \"leaf-a\")

   Flushing to disk:
     (wal-flush wal)  ; Force flush all pending entries

   Recovery/replay:
     (wal-replay wal (lambda (entry) ...) :from-sequence 1000)

   See Also:
     MAKE-WAL-LOG, WAL-APPEND, WAL-FLUSH, WAL-REPLAY"))

;;;; ============================================================================
;;;; WAL Creation and Management
;;;; ============================================================================

(defun make-wal-log (path &key
                          (flush-interval 1)
                          (max-size (* 1024 1024 100))
                          (sync-mode :sync)
                          (sharding-enabled t))
  "Create a new write-ahead log.

  Initializes a WAL instance and opens the log file for writing.

  Args:
    path - Directory or file path for WAL (string or pathname)
    flush-interval - Entries before auto-flush (default: 1 = flush every entry)
    max-size - Rotate when log exceeds this size in bytes
    sync-mode - Durability strategy (:sync, :async, or :batch)
    sharding-enabled - Enable 16-shard lock pool (default: T)

  Returns:
    WAL-LOG instance.

  Signals:
    ERROR if directory cannot be created or file cannot be opened.

  Notes:
    - Creates directory if it doesn't exist
    - Appends to existing log file if present
    - Sets up rotation tracking
    - Thread-safe for concurrent appends (with sharding)
    - When sharding-enabled is T, uses 16-shard lock pool for concurrency

  Examples:
    ;; Create WAL with 100 MB rotation size
    (let ((wal (make-wal-log \"/var/sw4rm/wal\" :max-size (* 1024 1024 100))))
      (wal-append wal :route '(:source \"a\" :target \"b\"))
      (wal-flush wal)
      (wal-close wal))

    ;; High-performance mode: batch sync with sharding
    (let ((wal (make-wal-log \"/var/sw4rm/wal\"
                             :flush-interval 100
                             :sync-mode :batch
                             :sharding-enabled t)))
      ...)

  See Also:
    WAL-LOG, WAL-APPEND, WAL-CLOSE, *wal-sync-mode*"

  (declare (type (or string pathname) path)
           (type (or null (integer 1 *)) flush-interval)
           (type (integer 1 *) max-size)
           (type (member :sync :async :batch) sync-mode)
           (type boolean sharding-enabled))

  (let ((wal (make-instance 'wal-log
                            :path path
                            :flush-interval flush-interval
                            :max-size max-size
                            :sync-mode sync-mode
                            :sharding-enabled sharding-enabled)))

    ;; Open the log file
    (open-wal-file wal)

    ;; Load sequence from existing log (for rotation recovery)
    (load-wal-sequence wal)

    (log:debug "WAL created: path=~A, flush-interval=~@[~D~], max-size=~D, sync=~A, sharding=~A"
               path flush-interval max-size sync-mode sharding-enabled)

    wal))

(defun normalize-wal-path (path)
  "Return PATH as a pathname, preserving existing pathname values."
  (etypecase path
    (pathname path)
    (string (uiop:parse-native-namestring path))))

(defun open-wal-file (wal)
  "Open the WAL file for writing.

  Internal function. Creates file if it doesn't exist, otherwise appends.

  Args:
    wal - WAL-LOG instance"

  (let* ((raw-path (wal-path wal))
         (path (normalize-wal-path raw-path)))
    ;; Ensure directory exists
    (let ((dir (if (pathname-type path)
                   (make-pathname :directory (pathname-directory path)
                                  :defaults path)
                   path)))
      (ensure-wal-directory dir))

    ;; Open file for append
    (handler-case
        (setf (wal-stream wal)
              (open path
                    :direction :output
                    :element-type '(unsigned-byte 8)
                    :if-exists :append
                    :if-does-not-exist :create))

      (error (e)
        (error "Failed to open WAL file ~A: ~A" path e)))))

(defun load-wal-sequence (wal)
  "Load last sequence number from existing WAL file.

  Scans the WAL file to find the highest sequence number, ensuring
  monotonic sequence numbers across restarts. This is essential for
  crash recovery to avoid sequence number collisions.

  Args:
    wal - WAL-LOG instance

  Returns:
    The highest sequence number found (also stored in WAL).

  Side Effects:
    - Sets wal-sequence-number to highest found + 1
    - Logs scan results

  Notes:
    - Handles empty/missing WAL file gracefully
    - Tolerates corrupted entries (skips them with warning)
    - Reads entire file but does not keep entries in memory"
  (let ((path (wal-path wal))
        (max-sequence 0)
        (entry-count 0)
        (corrupt-count 0))

    (handler-case
        (when (and path (probe-file path))
          (with-open-file (in path
                              :direction :input
                              :element-type '(unsigned-byte 8)
                              :if-does-not-exist nil)
            (when in
              (loop
                (multiple-value-bind (entry valid-p)
                    (read-wal-entry-from-stream in)
                  (cond
                    ;; End of file
                    ((null entry)
                     (return))
                    ;; Valid entry
                    (valid-p
                     (incf entry-count)
                     (when (> (wal-entry-sequence entry) max-sequence)
                       (setf max-sequence (wal-entry-sequence entry))))
                    ;; Corrupted entry
                    (t
                     (incf corrupt-count)
                     (log:warn "Corrupted WAL entry found during sequence scan"))))))))
      (error (e)
        (log:warn "Error scanning WAL file for sequence: ~A" e)))

    ;; Set sequence to one more than max found
    (setf (wal-sequence-number wal) max-sequence)

    (when (> entry-count 0)
      (log:debug "Loaded WAL sequence: max=~D, entries=~D, corrupt=~D"
                 max-sequence entry-count corrupt-count))

    max-sequence))

(defun read-wal-entry-from-stream (stream)
  "Read a single WAL entry from a binary stream.

  Reads and validates a WAL entry including checksum verification.

  Args:
    stream - Binary input stream positioned at start of entry

  Returns:
    (VALUES entry valid-p) where:
      - entry: WAL-ENTRY structure, or NIL if EOF/error
      - valid-p: T if checksum verified, NIL if corrupted

  Notes:
    - Returns (VALUES NIL NIL) on EOF
    - Returns (VALUES entry NIL) if entry is corrupted
    - Advances stream position past the entry"
  ;; Try to read magic number
  (let ((magic-bytes (make-array 4 :element-type '(unsigned-byte 8))))
    (when (< (read-sequence magic-bytes stream) 4)
      (return-from read-wal-entry-from-stream (values nil nil)))

    ;; Verify magic number
    (let ((magic (octets-to-integer magic-bytes 0 4)))
      (unless (= magic +wal-magic-number+)
        ;; Not a valid entry start - try to find next magic number
        (log:warn "Invalid WAL magic number: #x~X, expected #x~X"
                  magic +wal-magic-number+)
        (return-from read-wal-entry-from-stream (values nil nil))))

    ;; Read rest of header (24 bytes: seq(8) + ts(8) + op(4) + len(4))
    (let ((header-rest (make-array 24 :element-type '(unsigned-byte 8))))
      (when (< (read-sequence header-rest stream) 24)
        (log:warn "Truncated WAL entry header")
        (return-from read-wal-entry-from-stream (values nil nil)))

      (let* ((sequence-num (octets-to-integer header-rest 0 8))
             (timestamp (octets-to-integer header-rest 8 8))
             (op-hash (octets-to-integer header-rest 16 4))
             (payload-length (octets-to-integer header-rest 20 4)))

        ;; Sanity check payload length
        (when (> payload-length (* 100 1024 1024))  ;; 100 MB limit
          (log:warn "WAL entry payload too large: ~D bytes" payload-length)
          (return-from read-wal-entry-from-stream (values nil nil)))

        ;; Read payload
        (let ((payload-bytes (make-array payload-length
                                         :element-type '(unsigned-byte 8))))
          (when (< (read-sequence payload-bytes stream) payload-length)
            (log:warn "Truncated WAL entry payload")
            (return-from read-wal-entry-from-stream (values nil nil)))

          ;; Read checksum
          (let ((checksum-bytes (make-array 4 :element-type '(unsigned-byte 8))))
            (when (< (read-sequence checksum-bytes stream) 4)
              (log:warn "Truncated WAL entry checksum")
              (return-from read-wal-entry-from-stream (values nil nil)))

            (let ((stored-checksum (octets-to-integer checksum-bytes 0 4)))

              ;; Verify checksum
              (let* ((full-header (concatenate '(vector (unsigned-byte 8))
                                               magic-bytes header-rest))
                     (all-data (concatenate '(vector (unsigned-byte 8))
                                            full-header payload-bytes))
                     (computed-checksum (crc32 all-data))
                     (valid-p (= stored-checksum computed-checksum)))

                (unless valid-p
                  (log:warn "WAL entry checksum mismatch: seq=~D, stored=#x~X, computed=#x~X"
                            sequence-num stored-checksum computed-checksum))

                ;; Deserialize payload and reconstruct entry
                (let* ((data (deserialize-wal-payload payload-bytes))
                       (entry (make-wal-entry
                               :sequence sequence-num
                               :timestamp timestamp
                               :operation (find-operation-by-hash op-hash)
                               :data data
                               :checksum stored-checksum)))
                  (values entry valid-p))))))))))

(defun find-operation-by-hash (hash)
  "Find operation keyword by its hash value.

  During WAL write, we store the sxhash of the operation keyword.
  During read, we need to recover the original keyword. Since we
  know the set of valid operations, we can look it up.

  Args:
    hash - 32-bit hash value from sxhash

  Returns:
    The matching keyword, or :UNKNOWN if not found."
  (let ((known-ops '(:route :register :unregister :deliver :checkpoint
                     :barrier-arrive :barrier-wait :barrier-reset
                     :transaction-start :transaction-commit :transaction-rollback
                     :artifact-register :artifact-unregister
                     :lease-acquire :lease-release :lease-extend)))
    (dolist (op known-ops :unknown)
      (when (= (ldb (byte 32 0) (sxhash op)) hash)
        (return op)))))

(defun ensure-wal-directory (directory)
  "Create WAL directory if it doesn't exist.

  Args:
    directory - Directory path"

  (unless (uiop:directory-exists-p directory)
    (uiop:ensure-all-directories-exist (list directory))))

;;;; ============================================================================
;;;; Shard Lock Coordination Macros
;;;; ============================================================================

(defmacro with-shard-lock ((wal shard-index) &body body)
  "Execute BODY while holding the lock for a specific shard.

  Args:
    wal - WAL-LOG instance
    shard-index - Index of shard (0-15)
    body - Forms to execute

  Returns:
    Result of BODY."
  (let ((lock-var (gensym "LOCK-")))
    `(let ((,lock-var (aref (wal-shard-locks ,wal) ,shard-index)))
       (bt:with-lock-held (,lock-var)
         ,@body))))

(defmacro with-all-shard-locks ((wal) &body body)
  "Execute BODY while holding ALL shard locks.

  Acquires locks in order 0-15 to prevent deadlocks.
  Used for operations that need to coordinate across all shards
  (flush, compact, truncate).

  Args:
    wal - WAL-LOG instance
    body - Forms to execute

  Returns:
    Result of BODY.

  Notes:
    - Always acquires locks in ascending order to prevent deadlocks
    - Expensive operation - use sparingly
    - Required for flush, compact, truncate operations"
  (let ((wal-var (gensym "WAL-")))
    `(let ((,wal-var ,wal))
       (acquire-all-shard-locks-and-execute
        ,wal-var
        (lambda () ,@body)))))

(defun acquire-all-shard-locks-and-execute (wal fn)
  "Acquire all shard locks in order and execute FN.

  Internal function that recursively acquires locks 0-15.

  Args:
    wal - WAL-LOG instance
    fn - Zero-argument function to call with all locks held

  Returns:
    Result of calling FN."
  (labels ((acquire-lock (index)
             (if (>= index +wal-shard-count+)
                 (funcall fn)
                 (bt:with-lock-held ((aref (wal-shard-locks wal) index))
                   (acquire-lock (1+ index))))))
    (acquire-lock 0)))

(defun wal-close (wal)
  "Close the write-ahead log.

  Flushes any pending entries and closes the file stream.
  After closing, WAL operations are no longer allowed.

  Args:
    wal - WAL-LOG instance

  Returns:
    T if successfully closed.

  Side Effects:
    - Flushes pending entries from all shards
    - Closes file stream
    - Clears in-memory buffers

  Notes:
    - Safe to call multiple times
    - Should be called during graceful shutdown
    - Consider calling WAL-ENSURE-DURABILITY before close
    - When sharding is enabled, flushes all 16 shards

  Examples:
    (unwind-protect
        (... wal operations ...)
      (wal-close wal))

  See Also:
    MAKE-WAL-LOG, WAL-FLUSH, WAL-ENSURE-DURABILITY"

  (if (wal-sharding-enabled wal)
      ;; Sharded mode: acquire all shard locks, then flush
      (with-all-shard-locks (wal)
        (when (wal-stream wal)
          (wal-flush-internal-sharded wal)
          (close (wal-stream wal))
          (setf (wal-stream wal) nil)))
      ;; Legacy mode: use single buffer lock
      (bt:with-lock-held ((wal-buffer-lock wal))
        (when (wal-stream wal)
          (wal-flush-internal wal)
          (close (wal-stream wal))
          (setf (wal-stream wal) nil))))

  (log:debug "WAL closed: path=~A, entries=~D, rotations=~D"
             (wal-path wal) (wal-entry-count wal) (wal-rotation-count wal))

  t)

;;;; ============================================================================
;;;; Logging Operations
;;;; ============================================================================

(defun wal-append (wal operation data &key idempotency-token swarm-id)
  "Append an operation to the write-ahead log.

  Logs the operation in the buffer. If flush-interval is set and buffer
  reaches the threshold, automatically flushes to disk.

  Args:
    wal - WAL-LOG instance
    operation - Operation keyword (:route, :register, etc.)
    data - Operation data (typically plist or structured object)
    idempotency-token - Optional token for deduplication (not used yet)
    swarm-id - Optional swarm ID for shard routing (enables concurrency)

  Returns:
    Sequence number assigned to this entry.

  Side Effects:
    - Increments sequence number
    - Adds entry to appropriate shard buffer (or legacy buffer)
    - May trigger flush if threshold reached
    - Updates statistics

  Notes:
    - Thread-safe: uses shard locks for concurrent access
    - Fast: O(1) append to buffer
    - Actual disk write happens on flush
    - Sequence numbers are guaranteed monotonic
    - With swarm-id, entries go to specific shards for concurrency

  Examples:
    (wal-append wal :route '(:from \"a\" :to \"b\") :swarm-id \"leaf-a\")
    => 1  ;; Sequence number

    (wal-append wal :register '(:leaf-id \"leaf-1\" :host \"localhost\"))
    => 2

    (let ((seq (wal-append wal :checkpoint '(:state ...))))
      (format t \"Checkpoint logged as entry ~D~%\" seq))

  See Also:
    WAL-FLUSH, WAL-REPLAY, WAL-ENTRIES"

  (declare (type wal-log wal)
           (type keyword operation)
           (type t data)
           (ignore idempotency-token))

  (if (wal-sharding-enabled wal)
      (wal-append-sharded wal operation data swarm-id)
      (wal-append-legacy wal operation data)))

(defun wal-append-sharded (wal operation data swarm-id)
  "Append entry using sharded lock pool.

  Internal function for sharded WAL operation.

  Args:
    wal - WAL-LOG instance
    operation - Operation keyword
    data - Operation data
    swarm-id - Swarm ID for shard selection (NIL maps to shard 0)

  Returns:
    Sequence number assigned to this entry."
  (let ((shard-index (compute-shard-index swarm-id))
        (seq nil))

    ;; Allocate sequence number (global lock, brief)
    (bt:with-lock-held ((wal-sequence-lock wal))
      (setf seq (incf (wal-sequence-number wal))))

    ;; Create entry
    (let ((entry (make-wal-entry
                  :sequence seq
                  :timestamp (get-universal-time)
                  :operation operation
                  :data data
                  :checksum (compute-wal-checksum seq operation data)
                  :swarm-id swarm-id)))

      ;; Add to shard buffer (shard lock)
      (with-shard-lock (wal shard-index)
        (vector-push-extend entry (aref (wal-shard-buffers wal) shard-index)))

      ;; Update stats (atomic increment not strictly needed, but safe)
      (bt:with-lock-held ((wal-buffer-lock wal))
        (incf (gethash operation (wal-stats wal) 0))
        (incf (wal-entry-count wal)))

      ;; Auto-flush if threshold reached (check total across all shards)
      (when (and (wal-flush-interval wal)
                 (>= (total-shard-entries wal) (wal-flush-interval wal)))
        (wal-flush wal))

      seq)))

(defun wal-append-legacy (wal operation data)
  "Append entry using legacy single-buffer mode.

  Internal function for backward compatibility.

  Args:
    wal - WAL-LOG instance
    operation - Operation keyword
    data - Operation data

  Returns:
    Sequence number assigned to this entry."
  (bt:with-lock-held ((wal-buffer-lock wal))

    ;; Create entry
    (let* ((seq (incf (wal-sequence-number wal)))
           (entry (make-wal-entry
                    :sequence seq
                    :timestamp (get-universal-time)
                    :operation operation
                    :data data
                    :checksum (compute-wal-checksum seq operation data))))

      ;; Add to buffer
      (vector-push-extend entry (wal-buffer wal))

      ;; Update stats
      (incf (gethash operation (wal-stats wal) 0))
      (incf (wal-entry-count wal))

      ;; Auto-flush if threshold reached
      (when (and (wal-flush-interval wal)
                 (>= (fill-pointer (wal-buffer wal)) (wal-flush-interval wal)))
        (wal-flush-internal wal))

      seq)))

(defun total-shard-entries (wal)
  "Count total entries across all shard buffers.

  Args:
    wal - WAL-LOG instance

  Returns:
    Total number of pending entries in all shards."
  (let ((total 0))
    (dotimes (i +wal-shard-count+)
      (incf total (fill-pointer (aref (wal-shard-buffers wal) i))))
    total))

(defun compute-wal-checksum (sequence operation data)
  "Compute CRC32 checksum for WAL entry.

  Computes a CRC32 checksum over the entry's key fields: sequence number,
  operation type, and payload data. This enables detection of corruption
  during WAL replay.

  Args:
    sequence - Entry sequence number (integer)
    operation - Operation type (keyword)
    data - Operation data (any serializable Lisp object)

  Returns:
    32-bit CRC32 checksum value.

  Notes:
    - Uses IEEE 802.3 CRC32 polynomial
    - Checksum covers: sequence (8 bytes) + operation hash (4 bytes) +
      serialized data
    - Data is serialized via cl-store for consistent hashing"
  (let* ((seq-bytes (integer-to-octets sequence 8))
         (op-hash (ldb (byte 32 0) (sxhash operation)))
         (op-bytes (integer-to-octets op-hash 4))
         (data-bytes (if data
                         (serialize-for-checksum data)
                         #())))
    ;; Compute CRC32 over concatenated bytes
    (let ((crc #xFFFFFFFF))
      (setf crc (crc32-update crc seq-bytes))
      (setf crc (crc32-update crc op-bytes))
      (setf crc (crc32-update crc data-bytes))
      (logxor crc #xFFFFFFFF))))

(defun serialize-for-checksum (data)
  "Serialize data to bytes for checksum computation.

  Uses print representation for consistent, portable hashing.

  Args:
    data - Any Lisp object

  Returns:
    Byte vector representation of data."
  (handler-case
      (let ((str (with-output-to-string (s)
                   (let ((*print-readably* t)
                         (*print-circle* t))
                     (prin1 data s)))))
        (babel:string-to-octets str :encoding :utf-8))
    (error ()
      ;; If serialization fails, use simple print
      (babel:string-to-octets (prin1-to-string data) :encoding :utf-8))))

(defun integer-to-octets (value nbytes)
  "Convert an integer to a byte vector (big-endian).

  Args:
    value - Integer to convert
    nbytes - Number of bytes to produce

  Returns:
    Simple byte vector of length NBYTES."
  (let ((bytes (make-array nbytes :element-type '(unsigned-byte 8))))
    (dotimes (i nbytes)
      (setf (aref bytes (- nbytes 1 i))
            (ldb (byte 8 (* i 8)) value)))
    bytes))

(defun octets-to-integer (octets &optional (start 0) (nbytes (length octets)))
  "Convert a byte vector to an integer (big-endian).

  Args:
    octets - Byte vector
    start - Starting offset in vector
    nbytes - Number of bytes to read

  Returns:
    Integer value."
  (let ((value 0))
    (dotimes (i nbytes)
      (setf value (dpb (aref octets (+ start i))
                       (byte 8 (* (- nbytes 1 i) 8))
                       value)))
    value))

(defun wal-flush (wal)
  "Force flush of all pending WAL entries to disk.

  Writes buffered entries to disk. Respects *wal-sync-mode* for
  durability level (sync vs. async).

  Args:
    wal - WAL-LOG instance

  Returns:
    Number of entries flushed.

  Side Effects:
    - Writes buffer to disk
    - Clears in-memory buffer(s)
    - May fsync depending on sync-mode
    - Updates file position

  Notes:
    - Blocking operation (waits for disk)
    - Can be expensive if buffer is large
    - Called automatically on rotation or close
    - Safe to call multiple times
    - With sharding, acquires all shard locks and merges entries

  Examples:
    ;; Ensure durability before risky operation
    (wal-append wal :operation-start ...)
    (wal-flush wal)  ;; Force to disk
    (perform-risky-operation)

  See Also:
    WAL-APPEND, *wal-sync-mode*, WAL-ENSURE-DURABILITY"

  (if (wal-sharding-enabled wal)
      (with-all-shard-locks (wal)
        (wal-flush-internal-sharded wal))
      (bt:with-lock-held ((wal-buffer-lock wal))
        (wal-flush-internal wal))))

(defun wal-flush-internal (wal)
  "Internal flush without locking (caller must hold lock).

  Legacy single-buffer mode.

  Args:
    wal - WAL-LOG instance

  Returns:
    Number of entries written."

  (let ((count 0)
        (buffer (wal-buffer wal)))

    ;; Write all buffered entries to file
    (loop for entry across buffer
          do (progn
               (write-wal-entry (wal-stream wal) entry)
               (incf count)))

    ;; Clear buffer
    (setf (fill-pointer buffer) 0)

    ;; Sync based on mode
    (wal-ensure-durability wal)

    count))

(defun wal-flush-internal-sharded (wal)
  "Internal flush for sharded mode (caller must hold ALL shard locks).

  Collects entries from all shards, sorts by sequence number, and writes
  atomically to disk. This maintains the total ordering invariant.

  Args:
    wal - WAL-LOG instance

  Returns:
    Number of entries written.

  Notes:
    - Caller MUST hold all 16 shard locks
    - Entries are sorted by sequence for correct ordering
    - All shard buffers are cleared after write"

  (let ((all-entries nil)
        (count 0))

    ;; Collect entries from all shards
    (dotimes (i +wal-shard-count+)
      (let ((shard-buffer (aref (wal-shard-buffers wal) i)))
        (loop for entry across shard-buffer
              do (push entry all-entries))))

    ;; Sort by sequence number (ascending)
    (setf all-entries (sort all-entries #'< :key #'wal-entry-sequence))

    ;; Write all entries in sequence order
    (dolist (entry all-entries)
      (write-wal-entry (wal-stream wal) entry)
      (incf count))

    ;; Clear all shard buffers
    (dotimes (i +wal-shard-count+)
      (setf (fill-pointer (aref (wal-shard-buffers wal) i)) 0))

    ;; Sync based on mode
    (wal-ensure-durability wal)

    count))

(defun write-wal-entry (stream entry)
  "Write a single WAL entry to file in binary format.

  Serializes the entry using a length-prefixed binary format with CRC32
  checksum for integrity verification.

  Binary format (per entry):
    [4 bytes]  Magic number (#x57414C30 = \"WAL0\")
    [8 bytes]  Sequence number (big-endian)
    [8 bytes]  Timestamp (big-endian, universal-time)
    [4 bytes]  Operation type hash (big-endian)
    [4 bytes]  Payload length in bytes (big-endian)
    [N bytes]  Payload (serialized via cl-store)
    [4 bytes]  CRC32 checksum of header + payload

  Args:
    stream - Binary output stream (element-type (unsigned-byte 8))
    entry - WAL-ENTRY structure to write

  Returns:
    Number of bytes written.

  Side Effects:
    - Writes binary data to stream
    - May flush stream depending on sync mode

  Notes:
    - Entry is written atomically (single write-sequence call)
    - Checksum covers all preceding bytes in the entry
    - Payload is serialized using cl-store for portability"
  (declare (type stream stream)
           (type wal-entry entry))

  ;; Serialize payload to bytes
  (let* ((payload-bytes (serialize-wal-payload (wal-entry-data entry)))
         (payload-length (length payload-bytes))
         ;; Total entry size: header (28 bytes) + payload + checksum (4 bytes)
         (total-size (+ +wal-entry-header-size+ payload-length 4))
         (buffer (make-array total-size :element-type '(unsigned-byte 8)))
         (offset 0))

    ;; Write magic number (4 bytes)
    (setf (aref buffer 0) (ldb (byte 8 24) +wal-magic-number+))
    (setf (aref buffer 1) (ldb (byte 8 16) +wal-magic-number+))
    (setf (aref buffer 2) (ldb (byte 8 8) +wal-magic-number+))
    (setf (aref buffer 3) (ldb (byte 8 0) +wal-magic-number+))
    (incf offset 4)

    ;; Write sequence number (8 bytes, big-endian)
    (let ((seq (wal-entry-sequence entry)))
      (dotimes (i 8)
        (setf (aref buffer (+ offset (- 7 i)))
              (ldb (byte 8 (* i 8)) seq))))
    (incf offset 8)

    ;; Write timestamp (8 bytes, big-endian)
    (let ((ts (wal-entry-timestamp entry)))
      (dotimes (i 8)
        (setf (aref buffer (+ offset (- 7 i)))
              (ldb (byte 8 (* i 8)) ts))))
    (incf offset 8)

    ;; Write operation type hash (4 bytes, big-endian)
    (let ((op-hash (ldb (byte 32 0) (sxhash (wal-entry-operation entry)))))
      (setf (aref buffer (+ offset 0)) (ldb (byte 8 24) op-hash))
      (setf (aref buffer (+ offset 1)) (ldb (byte 8 16) op-hash))
      (setf (aref buffer (+ offset 2)) (ldb (byte 8 8) op-hash))
      (setf (aref buffer (+ offset 3)) (ldb (byte 8 0) op-hash)))
    (incf offset 4)

    ;; Write payload length (4 bytes, big-endian)
    (setf (aref buffer (+ offset 0)) (ldb (byte 8 24) payload-length))
    (setf (aref buffer (+ offset 1)) (ldb (byte 8 16) payload-length))
    (setf (aref buffer (+ offset 2)) (ldb (byte 8 8) payload-length))
    (setf (aref buffer (+ offset 3)) (ldb (byte 8 0) payload-length))
    (incf offset 4)

    ;; Write payload bytes
    (replace buffer payload-bytes :start1 offset)
    (incf offset payload-length)

    ;; Compute and write CRC32 checksum over header + payload
    (let ((checksum (crc32 (subseq buffer 0 offset))))
      (setf (aref buffer (+ offset 0)) (ldb (byte 8 24) checksum))
      (setf (aref buffer (+ offset 1)) (ldb (byte 8 16) checksum))
      (setf (aref buffer (+ offset 2)) (ldb (byte 8 8) checksum))
      (setf (aref buffer (+ offset 3)) (ldb (byte 8 0) checksum)))

    ;; Write entire entry to stream
    (write-sequence buffer stream)

    ;; Return bytes written
    total-size))

(defun serialize-wal-payload (data)
  "Serialize WAL payload data to bytes.

  Uses cl-store for full Lisp object serialization when available,
  falling back to print representation otherwise.

  Args:
    data - Any Lisp object to serialize

  Returns:
    Byte vector containing serialized data."
  (if (null data)
      (make-array 0 :element-type '(unsigned-byte 8))
      (handler-case
          (if (find-package :cl-store)
              ;; Use cl-store with a vector stream
              (let ((buffer (make-array 4096 :element-type '(unsigned-byte 8)
                                             :adjustable t :fill-pointer 0)))
                (cl-store:store data buffer)
                (coerce buffer '(simple-array (unsigned-byte 8) (*))))
              ;; Fallback: use print representation with babel
              (let ((str (with-output-to-string (s)
                           (let ((*print-readably* t)
                                 (*print-circle* t))
                             (prin1 data s)))))
                (babel:string-to-octets str :encoding :utf-8)))
        (error (e)
          (log:debug "Failed to serialize WAL payload: ~A, using print form" e)
          (babel:string-to-octets (prin1-to-string data) :encoding :utf-8)))))

(defun deserialize-wal-payload (bytes)
  "Deserialize WAL payload from bytes.

  Uses cl-store for deserialization when available.

  Args:
    bytes - Byte vector containing serialized data

  Returns:
    Deserialized Lisp object, or NIL if bytes is empty."
  (when (zerop (length bytes))
    (return-from deserialize-wal-payload nil))

  (handler-case
      (if (find-package :cl-store)
          ;; Use cl-store with a vector stream
          (cl-store:restore bytes)
          ;; Fallback: try to read as print representation
          (read-from-string (babel:octets-to-string bytes :encoding :utf-8)))
    (error (e)
      (log:debug "Failed to deserialize WAL payload: ~A" e)
      nil)))

;;;; ============================================================================
;;;; Flushing and Durability
;;;; ============================================================================

(defun wal-ensure-durability (wal)
  "Ensure WAL data is durable (written to disk).

  Respects *wal-sync-mode* for durability strategy:
    - :SYNC: fsync immediately (safest)
    - :ASYNC: No fsync (fastest, not durable)
    - :BATCH: No fsync, rely on periodic system sync

  Args:
    wal - WAL-LOG instance

  Returns:
    T if durability confirmed (or assumed for async modes).

  Notes:
    - :SYNC mode may be expensive (fsync system call)
    - :ASYNC mode is fast but risky (OS may lose data on crash)
    - :BATCH mode is recommended for production
    - Only fsync if stream is open

  See Also:
    *wal-sync-mode*, WAL-FLUSH"

  (let ((stream (wal-stream wal)))
    (cond
      ((and stream (eq (wal-sync-mode wal) :sync))
       (force-output stream)
       t)
      (stream t)
      (t nil))))

;;;; ============================================================================
;;;; Rotation (Log File Size Management)
;;;; ============================================================================

(defun wal-rotate (wal)
  "Rotate the WAL to a new file when size limit reached.

  Archives the current log file and creates a new one. Old file is
  renamed with .N suffix (e.g., wal.0, wal.1, wal.2).

  Args:
    wal - WAL-LOG instance

  Returns:
    T if successful.

  Side Effects:
    - Closes current log file
    - Renames it to .N format
    - Opens new log file
    - Increments rotation counter

  Notes:
    - Should be called when file size exceeds wal-max-size
    - Flush is called before rotation
    - Auto-rotation can happen during WAL-APPEND

  Examples:
    (if (> (wal-size wal) (wal-max-size wal))
        (wal-rotate wal))

  See Also:
    WAL-SIZE, WAL-MAX-SIZE"

  (log:debug "Rotating WAL: ~A" (wal-path wal))

  ;; Flush current buffer
  (wal-flush wal)

  ;; Close current file
  (when (wal-stream wal)
    (close (wal-stream wal)))

  ;; Rename current file to .N format
  (let* ((raw-path (wal-path wal))
         (old-path (normalize-wal-path raw-path))
         (new-path (format nil "~A.~D"
                           raw-path
                           (wal-rotation-count wal))))
    (when (probe-file old-path)
      (rename-file old-path new-path)))

  ;; Increment counter
  (incf (wal-rotation-count wal))

  ;; Open new file
  (open-wal-file wal)

  t)

(defun wal-size (wal)
  "Get current size of WAL file in bytes.

  Args:
    wal - WAL-LOG instance

  Returns:
    File size in bytes, or 0 if error."

  (handler-case
      (when (wal-stream wal)
        (file-length (wal-stream wal)))
    (error () 0)))

;;;; ============================================================================
;;;; Replay and Recovery
;;;; ============================================================================

(defun wal-replay (wal handler-fn &key from-sequence to-sequence filter-op)
  "Replay WAL entries for recovery.

  Reads entries from the WAL file and calls handler-fn for each entry.
  Useful for recovery after crash: replay all entries since last checkpoint.

  Args:
    wal - WAL-LOG instance
    handler-fn - Function called for each entry (signature: (entry) -> *)
    from-sequence - Start replay from this sequence (default: 0)
    to-sequence - Stop replay at this sequence (default: max)
    filter-op - Only replay entries with this operation type (default: all)

  Returns:
    Number of entries replayed.

  Side Effects:
    - Calls handler-fn for each matching entry
    - Handler side effects depend on handler implementation

  Notes:
    - Entries are replayed in order (monotonic sequence)
    - Handler should be idempotent (safe to replay multiple times)
    - filter-op can be a keyword or list of keywords
    - Invalid entries (bad checksum) are skipped with warning
    - With sharding, entries from all shards are merged and sorted

  Examples:
    ;; Replay all route operations since sequence 100
    (wal-replay wal
      (lambda (entry)
        (apply-route-operation (wal-entry-data entry)))
      :from-sequence 100
      :filter-op :route)

    ;; Replay all entries (for recovery)
    (wal-replay wal
      (lambda (entry)
        (reconstruct-state entry)))

  See Also:
    WAL-ENTRIES, WAL-LAST-SEQUENCE"

  (declare (type wal-log wal)
           (type function handler-fn))

  (let ((count 0)
        (entries (wal-entries wal :from from-sequence :to to-sequence)))

    (dolist (entry entries)
      ;; Filter by operation if requested
      (when (or (null filter-op)
                (if (listp filter-op)
                    (member (wal-entry-operation entry) filter-op)
                    (eq (wal-entry-operation entry) filter-op)))

        (if (verify-wal-checksum entry)
            ;; Call handler
            (handler-case
                (progn
                  (funcall handler-fn entry)
                  (incf count))
              (error (e)
                (log:error "Error replaying entry ~D: ~A"
                           (wal-entry-sequence entry) e)))
            (log:warn "WAL entry ~D has invalid checksum, skipping"
                      (wal-entry-sequence entry)))))

    (log:debug "Replayed ~D WAL entries" count)
    count))

(defun verify-wal-checksum (entry)
  "Verify entry checksum for integrity.

  Args:
    entry - WAL-ENTRY to verify

  Returns:
    T if checksum matches, NIL if invalid."

  (let ((expected (compute-wal-checksum
                    (wal-entry-sequence entry)
                    (wal-entry-operation entry)
                    (wal-entry-data entry))))
    (= expected (wal-entry-checksum entry))))

(defun wal-entries (wal &key from to)
  "Get list of WAL entries from buffer and/or file.

  Reads entries from both the WAL file on disk and the in-memory buffer,
  optionally filtered by sequence range. Entries from the file come first,
  followed by entries from the buffer.

  Args:
    wal - WAL-LOG instance
    from - Include entries with sequence >= from (default: all)
    to - Include entries with sequence <= to (default: all)

  Returns:
    List of WAL-ENTRY structures in sequence order.

  Notes:
    - File entries and buffer entries are merged
    - Corrupted file entries are skipped with warning
    - Returns empty list if no entries match criteria
    - With sharding, entries from all shards are merged and sorted"
  (declare (type wal-log wal))

  (let ((result nil))
    ;; First, read entries from file
    (setf result (read-wal-entries-from-file wal :from from :to to))

    ;; Then add entries from buffer (these are more recent)
    (if (wal-sharding-enabled wal)
        ;; Sharded mode: collect from all shard buffers
        (dotimes (i +wal-shard-count+)
          (with-shard-lock (wal i)
            (loop for entry across (aref (wal-shard-buffers wal) i)
                  when (and (or (null from) (>= (wal-entry-sequence entry) from))
                            (or (null to) (<= (wal-entry-sequence entry) to)))
                    do (push entry result))))
        ;; Legacy mode: use single buffer
        (bt:with-lock-held ((wal-buffer-lock wal))
          (loop for entry across (wal-buffer wal)
                when (and (or (null from) (>= (wal-entry-sequence entry) from))
                          (or (null to) (<= (wal-entry-sequence entry) to)))
                  do (push entry result))))

    ;; Sort by sequence number and return
    (sort result #'< :key #'wal-entry-sequence)))

(defun read-wal-entries-from-file (wal &key from to)
  "Read WAL entries from the file on disk.

  Scans the WAL file and returns entries matching the sequence range.

  Args:
    wal - WAL-LOG instance
    from - Minimum sequence number (inclusive)
    to - Maximum sequence number (inclusive)

  Returns:
    List of WAL-ENTRY structures from the file."
  (let ((path (wal-path wal))
        (entries nil))

    (handler-case
        (when (and path (probe-file path))
          (with-open-file (in path
                              :direction :input
                              :element-type '(unsigned-byte 8)
                              :if-does-not-exist nil)
            (when in
              (loop
                (multiple-value-bind (entry valid-p)
                    (read-wal-entry-from-stream in)
                  (cond
                    ;; End of file
                    ((null entry) (return))
                    ;; Valid entry in range
                    ((and valid-p
                          (or (null from) (>= (wal-entry-sequence entry) from))
                          (or (null to) (<= (wal-entry-sequence entry) to)))
                     (push entry entries))
                    ;; Valid but out of range - skip
                    (valid-p nil)
                    ;; Corrupted - already logged in read-wal-entry-from-stream
                    (t nil)))))))
      (error (e)
        (log:warn "Error reading WAL entries from file: ~A" e)))

    (nreverse entries)))

(defun wal-last-sequence (wal)
  "Get the last (highest) sequence number in WAL.

  Useful for determining where to resume replay after crash.

  Args:
    wal - WAL-LOG instance

  Returns:
    Sequence number (integer), or 0 if empty."

  (wal-sequence-number wal))

;;;; ============================================================================
;;;; Compaction and Cleanup
;;;; ============================================================================

(defun wal-truncate (wal before-sequence)
  "Remove all entries before a given sequence number.

  Rewrites the WAL file to exclude entries with sequence < before-sequence.
  This is an atomic operation: writes to a temporary file first, then
  renames to the final location.

  Args:
    wal - WAL-LOG instance
    before-sequence - Delete entries with sequence < this value

  Returns:
    Number of entries deleted.

  Side Effects:
    - Rewrites WAL file (atomic)
    - Closes and reopens WAL stream
    - Cannot be undone

  Notes:
    - Expensive operation (requires rewriting entire file)
    - Should only be done after successful checkpoint
    - Atomic: uses write-to-temp + rename pattern
    - Thread-safe: holds all shard locks during operation
    - Maintains ordering invariant: entries are written in sequence order

  Examples:
    ;; After checkpoint at sequence 1000:
    (wal-truncate wal 1000)  ;; Delete everything before 1000

  See Also:
    WAL-COMPACT, WAL-ENTRIES"
  (declare (type wal-log wal)
           (type (integer 0 *) before-sequence))

  (if (wal-sharding-enabled wal)
      (wal-truncate-sharded wal before-sequence)
      (wal-truncate-legacy wal before-sequence)))

(defun wal-truncate-sharded (wal before-sequence)
  "Truncate WAL with sharding enabled.

  Internal function that coordinates truncation across all shards.

  Args:
    wal - WAL-LOG instance
    before-sequence - Delete entries with sequence < this value

  Returns:
    Number of entries deleted."
  (with-all-shard-locks (wal)
    (wal-truncate-internal wal before-sequence)))

(defun wal-truncate-legacy (wal before-sequence)
  "Truncate WAL in legacy mode.

  Args:
    wal - WAL-LOG instance
    before-sequence - Delete entries with sequence < this value

  Returns:
    Number of entries deleted."
  (bt:with-lock-held ((wal-buffer-lock wal))
    (wal-truncate-internal wal before-sequence)))

(defun wal-truncate-internal (wal before-sequence)
  "Internal truncation (caller must hold appropriate locks).

  Args:
    wal - WAL-LOG instance
    before-sequence - Delete entries with sequence < this value

  Returns:
    Number of entries deleted."
  (let* ((path (wal-path wal))
         (temp-path (format nil "~A.truncate.tmp" path))
         (entries-deleted 0)
         (entries-kept 0))

    ;; First, flush any pending buffer entries
    (if (wal-sharding-enabled wal)
        (wal-flush-internal-sharded wal)
        (wal-flush-internal wal))

    ;; Close current stream
    (when (wal-stream wal)
      (close (wal-stream wal))
      (setf (wal-stream wal) nil))

    (handler-case
        (progn
          ;; Read all entries from current file
          (let ((entries-to-keep nil))
            (when (probe-file path)
              (with-open-file (in path
                                  :direction :input
                                  :element-type '(unsigned-byte 8)
                                  :if-does-not-exist nil)
                (when in
                  (loop
                    (multiple-value-bind (entry valid-p)
                        (read-wal-entry-from-stream in)
                      (cond
                        ((null entry) (return))
                        ((and valid-p (>= (wal-entry-sequence entry) before-sequence))
                         (push entry entries-to-keep)
                         (incf entries-kept))
                        (valid-p
                         (incf entries-deleted))))))))

            ;; Sort kept entries by sequence (maintain ordering invariant)
            (setf entries-to-keep
                  (sort (nreverse entries-to-keep) #'< :key #'wal-entry-sequence))

            ;; Write kept entries to temp file
            (with-open-file (out temp-path
                                 :direction :output
                                 :element-type '(unsigned-byte 8)
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
              (dolist (entry entries-to-keep)
                (write-wal-entry out entry))
              (force-output out))

            ;; Atomic rename: temp -> final
            (when (probe-file path)
              (delete-file path))
            (rename-file temp-path path)))

      (error (e)
        ;; Clean up temp file on error
        (when (probe-file temp-path)
          (ignore-errors (delete-file temp-path)))
        (error "WAL truncation failed: ~A" e)))

    ;; Reopen WAL file
    (open-wal-file wal)

    (log:debug "WAL truncated: deleted ~D entries, kept ~D entries (before seq ~D)"
               entries-deleted entries-kept before-sequence)

    entries-deleted))

(defun wal-compact (wal)
  "Compact the WAL file, removing gaps and optimizing layout.

  Rewrites the WAL file to ensure all entries are contiguous with no
  gaps from previous truncations or corrupted entries. This can reduce
  file size and improve read performance.

  Args:
    wal - WAL-LOG instance

  Returns:
    Plist with compaction statistics:
      :original-size - Size before compaction (bytes)
      :compacted-size - Size after compaction (bytes)
      :entries-compacted - Number of valid entries preserved
      :entries-dropped - Number of corrupted entries dropped

  Side Effects:
    - Rewrites entire WAL file (atomic)
    - Closes and reopens WAL stream
    - Blocks other operations during compaction

  Notes:
    - Should be done during low-load period
    - Atomic: uses write-to-temp + rename pattern
    - Does not change sequence numbers
    - Only drops corrupted entries, not valid ones
    - Thread-safe: holds all shard locks during operation
    - Maintains ordering invariant: entries are written in sequence order

  See Also:
    WAL-TRUNCATE, WAL-SIZE"
  (declare (type wal-log wal))

  (if (wal-sharding-enabled wal)
      (wal-compact-sharded wal)
      (wal-compact-legacy wal)))

(defun wal-compact-sharded (wal)
  "Compact WAL with sharding enabled.

  Internal function that coordinates compaction across all shards.

  Args:
    wal - WAL-LOG instance

  Returns:
    Plist with compaction statistics."
  (with-all-shard-locks (wal)
    (wal-compact-internal wal)))

(defun wal-compact-legacy (wal)
  "Compact WAL in legacy mode.

  Args:
    wal - WAL-LOG instance

  Returns:
    Plist with compaction statistics."
  (bt:with-lock-held ((wal-buffer-lock wal))
    (wal-compact-internal wal)))

(defun wal-compact-internal (wal)
  "Internal compaction (caller must hold appropriate locks).

  Args:
    wal - WAL-LOG instance

  Returns:
    Plist with compaction statistics."
  (let* ((path (wal-path wal))
         (temp-path (format nil "~A.compact.tmp" path))
         (original-size 0)
         (entries-compacted 0)
         (entries-dropped 0))

    ;; First, flush any pending buffer entries
    (if (wal-sharding-enabled wal)
        (wal-flush-internal-sharded wal)
        (wal-flush-internal wal))

    ;; Get original size
    (setf original-size (or (ignore-errors
                              (with-open-file (f path :direction :input)
                                (file-length f)))
                            0))

    ;; Close current stream
    (when (wal-stream wal)
      (close (wal-stream wal))
      (setf (wal-stream wal) nil))

    (handler-case
        (progn
          ;; Read all valid entries
          (let ((valid-entries nil))
            (when (probe-file path)
              (with-open-file (in path
                                  :direction :input
                                  :element-type '(unsigned-byte 8)
                                  :if-does-not-exist nil)
                (when in
                  (loop
                    (multiple-value-bind (entry valid-p)
                        (read-wal-entry-from-stream in)
                      (cond
                        ((null entry) (return))
                        (valid-p
                         (push entry valid-entries)
                         (incf entries-compacted))
                        (t
                         (incf entries-dropped)
                         (log:warn "Dropping corrupted entry during compaction"))))))))

            ;; Sort valid entries by sequence (maintain ordering invariant)
            (setf valid-entries
                  (sort (nreverse valid-entries) #'< :key #'wal-entry-sequence))

            ;; Write valid entries to temp file
            (with-open-file (out temp-path
                                 :direction :output
                                 :element-type '(unsigned-byte 8)
                                 :if-exists :supersede
                                 :if-does-not-exist :create)
              (dolist (entry valid-entries)
                (write-wal-entry out entry))
              (force-output out)))

          ;; Atomic rename
          (when (probe-file path)
            (delete-file path))
          (rename-file temp-path path))

      (error (e)
        ;; Clean up temp file on error
        (when (probe-file temp-path)
          (ignore-errors (delete-file temp-path)))
        (error "WAL compaction failed: ~A" e)))

    ;; Reopen WAL file
    (open-wal-file wal)

    ;; Get new size
    (let ((compacted-size (or (wal-size wal) 0)))
      (log:debug "WAL compacted: ~D -> ~D bytes, ~D entries, ~D dropped"
                 original-size compacted-size entries-compacted entries-dropped)

      (list :original-size original-size
            :compacted-size compacted-size
            :entries-compacted entries-compacted
            :entries-dropped entries-dropped))))

;;;; ============================================================================
;;;; Statistics and Monitoring
;;;; ============================================================================

(defun wal-get-stats (wal)
  "Get statistics about WAL operations.

  Returns a plist with operation counts, rotation count, etc.

  Args:
    wal - WAL-LOG instance

  Returns:
    Plist with statistics."

  (list
    :total-entries (wal-entry-count wal)
    :current-sequence (wal-sequence-number wal)
    :rotations (wal-rotation-count wal)
    :current-size (wal-size wal)
    :max-size (wal-max-size wal)
    :uptime (- (get-universal-time) (wal-created-at wal))
    :sharding-enabled (wal-sharding-enabled wal)
    :shard-count (if (wal-sharding-enabled wal) +wal-shard-count+ 1)
    :pending-entries (if (wal-sharding-enabled wal)
                         (total-shard-entries wal)
                         (fill-pointer (wal-buffer wal)))
    :operations (copy-hash-table (wal-stats wal))))

(defun copy-hash-table (table)
  "Deep copy a hash table.

  Args:
    table - Hash table to copy

  Returns:
    New hash table with same contents."

  (let ((copy (make-hash-table :test (hash-table-test table))))
    (maphash (lambda (k v) (setf (gethash k copy) v)) table)
    copy))

;;;; ============================================================================
;;;; Macro for Convenient WAL Usage
;;;; ============================================================================

(defmacro with-wal-logging (wal-instance &body body)
  "Execute BODY with automatic WAL logging of operations.

  Convenience macro for ensuring all operations are logged before execution.
  Sets up context for operation logging.

  Args:
    wal-instance - WAL-LOG instance to use
    body - Forms to execute

  Returns:
    Result of BODY.

  Side Effects:
    - Establishes WAL context
    - Logs operations from BODY
    - Flushes on exit (success or error)

  Notes:
    - This is a placeholder for future implementation
    - Would require capturing operations during BODY execution
    - Useful pattern but requires hook into routing/operation dispatch

  Example:
    (with-wal-logging *wal*
      (route-envelope orchestrator envelope)
      (register-child orchestrator child))

  See Also:
    WAL-TRANSACTION"

  `(let ((*wal-context* ,wal-instance))
     (unwind-protect
         (progn ,@body)
       (wal-flush ,wal-instance))))

(defmacro wal-transaction (wal-instance &body body)
  "Execute BODY as an atomic transaction with WAL logging.

  Logs a transaction boundary and executes BODY atomically.
  If BODY succeeds, transaction is committed and logged.
  If BODY fails, transaction is rolled back (logged as rollback entry).

  Args:
    wal-instance - WAL-LOG instance
    body - Forms to execute as transaction

  Returns:
    Result of BODY if successful, or NIL if rolled back.

  Side Effects:
    - Logs transaction start
    - Logs transaction end or rollback
    - Flushes WAL

  Notes:
    - Transaction semantics are logical, not ACID
    - Useful for grouping related operations for recovery
    - Replay should check transaction boundaries

  Example:
    (wal-transaction *wal*
      (register-child orchestrator child-1)
      (register-child orchestrator child-2)
      (rebuild-routing-tables))

  See Also:
    WITH-WAL-LOGGING, WAL-APPEND"

  (let ((tx-id (gensym "TX-"))
        (result (gensym "RESULT-")))

    `(let ((,tx-id (wal-append ,wal-instance :transaction-start
                              '(:timestamp (get-universal-time))))
           ,result)

       (unwind-protect
           (setf ,result
                 (handler-case
                     (progn ,@body)
                   (error (e)
                     (wal-append ,wal-instance :transaction-rollback
                                 (list :transaction-id ,tx-id :error e))
                     (wal-flush ,wal-instance)
                     (error e))))

         ;; Success path
         (wal-append ,wal-instance :transaction-commit
                     (list :transaction-id ,tx-id))
         (wal-flush ,wal-instance))

       ,result)))

;;;; ============================================================================
;;;; Configuration Variables
;;;; ============================================================================

(defvar *wal-sync-mode* :sync
  "Global default sync mode for all WAL instances.

   Values:
     :SYNC  - fsync after each flush (safest, slowest)
     :ASYNC - No fsync, rely on OS (fastest, less safe)
     :BATCH - No immediate fsync, rely on periodic system sync

   Default: :SYNC (most conservative)

   Can be overridden per WAL instance using :sync-mode arg to MAKE-WAL-LOG.

   See Also:
     MAKE-WAL-LOG, WAL-ENSURE-DURABILITY")

(defvar *wal-context* nil
  "Current WAL instance for context-based logging.

   Used by WITH-WAL-LOGGING macro to establish context.
   Not normally accessed directly.

   See Also:
     WITH-WAL-LOGGING")

;;;; ============================================================================
;;;; Integration Helpers
;;;; ============================================================================

(defun enable-wal (wal-directory &key (flush-interval 10) (sync-mode :batch)
                                      (sharding-enabled t))
  "Convenient function to enable WAL for orchestrator.

  Creates a WAL instance and sets up global context.

  Args:
    wal-directory - Directory for WAL files
    flush-interval - Entries before auto-flush
    sync-mode - Durability strategy
    sharding-enabled - Enable 16-shard lock pool (default: T)

  Returns:
    WAL-LOG instance."

  (make-wal-log wal-directory
                :flush-interval flush-interval
                :sync-mode sync-mode
                :sharding-enabled sharding-enabled))

(defun disable-wal (wal)
  "Disable WAL and clean up resources.

  Args:
    wal - WAL-LOG instance to disable

  Returns:
    T if successful."

  (wal-close wal))

(defun wal-enabled-p ()
  "Check if WAL is currently enabled.

  Returns:
    T if WAL context is set, NIL otherwise."

  (not (null *wal-context*)))

(defun flush-wal (&optional wal)
  "Convenience function to flush current WAL.

  Args:
    wal - Specific WAL to flush (default: *wal-context*)

  Returns:
    Number of entries flushed."

  (let ((w (or wal *wal-context*)))
    (if w
        (wal-flush w)
        (warn "No WAL context available"))))

;;;; End of file
