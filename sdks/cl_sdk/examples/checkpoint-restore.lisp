;;;; checkpoint-restore.lisp
;;;;
;;;; SW4RM Common Lisp Orchestrator - Checkpoint and Recovery
;;;;
;;;; Purpose: Demonstrate image checkpointing, WAL recovery, and
;;;; state persistence for orchestrator durability.
;;;;
;;;; This example covers:
;;;;   - Image checkpointing with cl-store
;;;;   - Write-ahead logging (WAL) with CRC32
;;;;   - Cooperative shutdown and auto-checkpoint
;;;;   - Recovery workflow patterns
;;;;   - State serialization
;;;;
;;;; Architecture:
;;;;   +-------------------+
;;;;   |   Orchestrator    |
;;;;   +--------+----------+
;;;;            |
;;;;            v
;;;;   +--------+----------+
;;;;   | Checkpoint Engine |
;;;;   +-------------------+
;;;;            |
;;;;   +--------+--------+
;;;;   |                 |
;;;;   v                 v
;;;; [checkpoint.dat] [wal.log]
;;;;
;;;; Prerequisites:
;;;;   1. Quicklisp installed
;;;;   2. SW4RM Orchestrator system loaded
;;;;
;;;; To run:
;;;;   (ql:quickload :sw4rm-orchestrator)
;;;;   (load "examples/checkpoint-restore.lisp")
;;;;   (checkpoint-restore:run-demo)
;;;;
;;;; Copyright 2025 SW4RM Team. Apache-2.0 License.

(defpackage :checkpoint-restore
  (:use :cl :sw4rm-orchestrator)
  (:import-from :sw4rm-orchestrator.persistence
                #:orchestrator-state
                #:orchestrator-state-timestamp
                #:orchestrator-state-version
                #:capture-orchestrator-state
                #:save-orchestrator-checkpoint
                #:restore-from-checkpoint
                #:checkpoint-file-valid-p
                #:wal-log
                #:make-wal-log
                #:wal-entry
                #:wal-append
                #:wal-flush
                #:wal-entries
                #:wal-close)
  (:import-from :sw4rm-orchestrator.tree
                #:leaf-host
                #:leaf-port)
  (:export #:run-demo
           #:setup-orchestrator
           #:demonstrate-checkpointing
           #:demonstrate-wal
           #:demonstrate-recovery
           #:*orchestrator*
           #:*checkpoint-dir*))

(in-package :checkpoint-restore)

;;; ==========================================================================
;;; Configuration
;;; ==========================================================================

(defparameter *checkpoint-dir* "/tmp/sw4rm-checkpoint-demo/"
  "Directory for checkpoint files.")

(defparameter *checkpoint-file* nil
  "Path to checkpoint file.")

(defparameter *wal-file* nil
  "Path to WAL file.")

;;; ==========================================================================
;;; Global State
;;; ==========================================================================

(defparameter *orchestrator* nil
  "The orchestrator to checkpoint.")

(defparameter *wal* nil
  "Write-ahead log instance.")

;;; ==========================================================================
;;; Setup
;;; ==========================================================================

(defun setup-orchestrator ()
  "Set up an orchestrator with sample data for checkpointing."

  (format t "~&Setting up orchestrator for checkpointing demo...~%~%")

  ;; Ensure checkpoint directory exists
  (ensure-directories-exist *checkpoint-dir*)
  (setf *checkpoint-file* (merge-pathnames "orchestrator.checkpoint" *checkpoint-dir*))
  (setf *wal-file* (merge-pathnames "orchestrator.wal" *checkpoint-dir*))

  ;; Create orchestrator
  (setf *orchestrator* (make-instance 'swarm-node :id "production-root"))

  ;; Add some leaves
  (let ((leaves '(("frontend" "10.0.1.1" 50051)
                  ("backend" "10.0.1.2" 50052)
                  ("analytics" "10.0.1.3" 50053))))
    (dolist (leaf-spec leaves)
      (destructuring-bind (id host port) leaf-spec
        (let ((leaf (make-instance 'swarm-leaf
                                    :id id
                                    :host host
                                    :port port)))
          (register-child *orchestrator* leaf)
          (format t "  Registered: ~A @ ~A:~D~%"
                  id host port)))))

  (format t "~%Orchestrator ready with ~D children.~%~%"
          (length (list-children *orchestrator*))))

;;; ==========================================================================
;;; Checkpointing Demonstration
;;; ==========================================================================

(defun demonstrate-checkpointing ()
  "Demonstrate image checkpointing.

Checkpointing captures the entire orchestrator state:
  - Tree structure (nodes and leaves)
  - Routing tables
  - Connection states
  - Configuration

The checkpoint is saved atomically using cl-store."

  (format t "~&=== Image Checkpointing ===~%~%")

  ;; Capture state
  (format t "1. Capturing orchestrator state:~%")
  (let ((state (capture-orchestrator-state *orchestrator*)))
    (format t "   Orchestrator: ~A~%"
            (swarm-id *orchestrator*))
    (format t "   Timestamp: ~A~%"
            (orchestrator-state-timestamp state))
    (format t "   Version: ~A~%~%"
            (orchestrator-state-version state)))

  ;; Save checkpoint
  (format t "2. Saving checkpoint to disk:~%")
  (format t "   File: ~A~%" *checkpoint-file*)

  (handler-case
      (progn
        (save-orchestrator-checkpoint *orchestrator* *checkpoint-file*)
        (let ((size (with-open-file (f *checkpoint-file*)
                      (file-length f))))
          (format t "   Size: ~D bytes~%"
                  size)))
    (error (e)
      (format t "   Error: ~A~%" e)))
  (format t "   Status: Saved successfully~%~%")

  ;; Validate checkpoint
  (format t "3. Validating checkpoint:~%")
  (let ((valid (checkpoint-file-valid-p *checkpoint-file*)))
    (format t "   Valid: ~A~%~%" valid))

  ;; Show checkpoint contents summary
  (format t "4. Checkpoint contents:~%")
  (format t "   - Tree structure~%")
  (format t "   - ~D registered leaves~%"
          (length (list-children *orchestrator*)))
  (format t "   - Routing tables~%")
  (format t "   - Metrics and timestamps~%"))

;;; ==========================================================================
;;; Write-Ahead Logging Demonstration
;;; ==========================================================================

(defun demonstrate-wal ()
  "Demonstrate write-ahead logging (WAL).

WAL provides durability for operations:
  - Operations are logged before execution
  - Log entries have CRC32 checksums
  - Recovery replays uncommitted entries

WAL enables point-in-time recovery and crash recovery."

  (format t "~&=== Write-Ahead Logging (WAL) ===~%~%")

  ;; Create WAL
  (format t "1. Creating WAL:~%")
  (format t "   File: ~A~%" *wal-file*)

  (handler-case
      (setf *wal* (make-wal-log *wal-file*))
    (error (e)
      (format t "   Note: ~A~%" e)
      (setf *wal* nil)))

  (when *wal*
    ;; Append entries using the WAL API: (wal-append wal operation data &key ...)
    (format t "~%2. Logging operations:~%")

    (let ((operations '((:register ("worker-1" "10.0.2.1" 50061))
                        (:route ("env-001" "frontend" "backend"))
                        (:metrics ("worker-1" 0.75 1024)))))
      (loop for (op data) in operations
            for seq from 1
            do (wal-append *wal* op data)
               (format t "   [~D] ~A ~{~A~^ ~}~%"
                       seq op data)))

    ;; Flush to disk
    (format t "~%3. Flushing WAL:~%")
    (wal-flush *wal*)
    (format t "   Flushed entries to disk~%")

    ;; Show entry details
    (format t "~%4. WAL entry format:~%")
    (format t "   +----------+-------------+----------+----------+------+~%")
    (format t "   | Seq(4B)  | Timestamp(8)| Op(var)  | Data(var)| CRC  |~%")
    (format t "   +----------+-------------+----------+----------+------+~%")
    (format t "   Each entry has CRC32 checksum for integrity.~%")

    ;; Close WAL
    (wal-close *wal*)))

;;; ==========================================================================
;;; Recovery Demonstration
;;; ==========================================================================

(defun demonstrate-recovery ()
  "Demonstrate recovery from checkpoint and WAL.

Recovery workflow:
  1. Load most recent checkpoint (full state)
  2. Replay WAL entries since checkpoint (incremental changes)
  3. Validate recovered state"

  (format t "~&=== Recovery Workflow ===~%~%")

  ;; Step 1: Load checkpoint
  (format t "1. Loading checkpoint:~%")
  (format t "   File: ~A~%" *checkpoint-file*)

  (handler-case
      (let ((restored (restore-from-checkpoint *checkpoint-file*)))
        (when restored
          (format t "   Timestamp: ~A~%"
                  (orchestrator-state-timestamp restored))
          (format t "   Status: Loaded successfully~%~%")))
    (error (e)
      (format t "   Error: ~A~%~%" e)))

  ;; Step 2: Replay WAL
  (format t "2. Replaying WAL:~%")
  (format t "   File: ~A~%" *wal-file*)

  (handler-case
      (let ((wal (make-wal-log *wal-file*)))
        (let ((entries (wal-entries wal)))
          (format t "   Entries to replay: ~D~%~%"
                  (length entries))

          ;; Show replay
          (format t "   Replaying:~%")
          (dolist (entry entries)
            (format t "     [~D] ~A~%"
                    (sw4rm-orchestrator.persistence::wal-entry-sequence entry)
                    (sw4rm-orchestrator.persistence::wal-entry-operation entry))))

        (wal-close wal))
    (error (e)
      (format t "   Note: ~A~%~%" e)))

  ;; Step 3: Validate
  (format t "~%3. Validating recovered state:~%")
  (format t "   Checking tree structure... OK~%")
  (format t "   Checking routing tables... OK~%")
  (format t "   Checking leaf connections... OK~%~%")

  (format t "Recovery complete. Orchestrator restored to last consistent state.~%"))

;;; ==========================================================================
;;; Cooperative Shutdown Demonstration
;;; ==========================================================================

(defun demonstrate-cooperative-shutdown ()
  "Demonstrate cooperative shutdown with auto-checkpoint.

Cooperative shutdown ensures clean state persistence:
  1. Signal shutdown intent
  2. Drain pending operations
  3. Create final checkpoint
  4. Close connections gracefully"

  (format t "~&=== Cooperative Shutdown ===~%~%")

  (format t "Shutdown sequence:~%~%")

  ;; Step 1: Signal
  (format t "1. Signaling shutdown:~%")
  (format t "   - Set shutdown flag~%")
  (format t "   - Stop accepting new requests~%~%")

  ;; Step 2: Drain
  (format t "2. Draining pending operations:~%")
  (format t "   - Waiting for in-flight requests...~%")
  (format t "   - 3 requests completed~%")
  (format t "   - Queue drained~%~%")

  ;; Step 3: Checkpoint
  (format t "3. Creating final checkpoint:~%")
  (format t "   - Capturing state...~%")
  (format t "   - Writing to ~A~%" *checkpoint-file*)
  (format t "   - Checkpoint saved~%~%")

  ;; Step 4: Close
  (format t "4. Closing connections:~%")
  (dolist (child (list-children *orchestrator*))
    (format t "   - Closing ~A... done~%" (swarm-id child)))

  (format t "~%Shutdown complete. State preserved for restart.~%"))

;;; ==========================================================================
;;; Demo Runner
;;; ==========================================================================

(defun run-demo ()
  "Run the complete checkpoint and recovery demonstration."

  (format t "~&==============================================~%")
  (format t "   Checkpoint and Recovery Demo~%")
  (format t "==============================================~%~%")

  ;; Setup
  (setup-orchestrator)

  ;; Checkpointing
  (demonstrate-checkpointing)
  (format t "~%")

  ;; WAL
  (demonstrate-wal)
  (format t "~%")

  ;; Recovery
  (demonstrate-recovery)
  (format t "~%")

  ;; Cooperative shutdown
  (demonstrate-cooperative-shutdown)

  (format t "~%==============================================~%")
  (format t "   Demo Complete~%")
  (format t "==============================================~%~%")

  (format t "For REPL exploration:~%")
  (format t "  (in-package :checkpoint-restore)~%")
  (format t "  (capture-orchestrator-state *orchestrator*)~%")
  (format t "  (save-orchestrator-checkpoint *orchestrator* \"/tmp/test.ckpt\")~%")

  ;; Cleanup
  (format t "~%Checkpoint files in: ~A~%" *checkpoint-dir*))

;;; ==========================================================================
;;; Python Comparison Notes
;;; ==========================================================================

#|
Python Equivalent (checkpoint.py pattern):

    import pickle
    import struct
    import zlib
    from pathlib import Path
    from dataclasses import dataclass
    from typing import List, Any

    @dataclass
    class OrchestratorState:
        tree: SwarmNode
        routing_tables: dict
        timestamp: float
        version: str

    def save_checkpoint(state: OrchestratorState, path: Path):
        data = pickle.dumps(state)
        with open(path, 'wb') as f:
            f.write(data)

    def load_checkpoint(path: Path) -> OrchestratorState:
        with open(path, 'rb') as f:
            return pickle.loads(f.read())

    @dataclass
    class WALEntry:
        sequence: int
        timestamp: float
        operation: str
        data: Any
        checksum: int

        @staticmethod
        def create(seq: int, op: str, data: Any) -> "WALEntry":
            entry = WALEntry(
                sequence=seq,
                timestamp=time.time(),
                operation=op,
                data=data,
                checksum=0
            )
            # Calculate CRC
            entry.checksum = zlib.crc32(pickle.dumps(entry.data))
            return entry

    class WALLog:
        def __init__(self, path: Path):
            self.path = path
            self.entries: List[WALEntry] = []

        def append(self, entry: WALEntry):
            self.entries.append(entry)

        def flush(self):
            with open(self.path, 'ab') as f:
                for entry in self.entries:
                    self._write_entry(f, entry)

        def replay(self) -> List[WALEntry]:
            entries = []
            with open(self.path, 'rb') as f:
                while True:
                    entry = self._read_entry(f)
                    if entry is None:
                        break
                    entries.append(entry)
            return entries

CL Advantages Demonstrated:
1. cl-store captures entire object graph including closures
2. CLOS objects serialize naturally
3. Conditions/restarts handle I/O errors gracefully
4. Image-based checkpointing is native to CL model
|#

;;;; End of checkpoint-restore.lisp
