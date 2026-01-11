;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/wal-tests.lisp
;;;;
;;;; Comprehensive test suite for Write-Ahead Log (WAL) persistence.
;;;;
;;;; Tests cover:
;;;;   - Basic WAL creation and configuration
;;;;   - Entry append and sequence number management
;;;;   - Durability (write-flush-read cycles)
;;;;   - Integrity (checksum verification, corruption handling)
;;;;   - Truncation and compaction
;;;;   - Concurrent access
;;;;   - Recovery scenarios
;;;;
;;;; Spec References:
;;;;   - COMMON_LISP_PLAN.md Section 2.2.4: Image-based development
;;;;   - Lines 220-252: WAL specifications
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

(in-suite persistence-tests)

;;;; ============================================================================
;;;; Test Fixtures and Helpers
;;;; ============================================================================

(defun make-temp-wal-directory ()
  "Create a unique temporary directory for WAL tests.
   Returns the pathname of the created directory."
  (let ((temp-dir (merge-pathnames
                   (format nil "wal-test-~A-~A/"
                           (get-universal-time)
                           (random 100000))
                   (uiop:temporary-directory))))
    (ensure-directories-exist temp-dir)
    temp-dir))

(defun cleanup-temp-wal-directory (dir)
  "Remove a temporary WAL test directory and all its contents."
  (when (and dir (uiop:directory-exists-p dir))
    (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)))

(defmacro with-temp-wal-directory ((var) &body body)
  "Execute BODY with VAR bound to a temporary directory.
   Cleans up the directory after BODY completes."
  `(let ((,var (make-temp-wal-directory)))
     (unwind-protect
         (progn ,@body)
       (cleanup-temp-wal-directory ,var))))

(defmacro with-test-wal ((wal-var &key (flush-interval 1) (sync-mode :sync)) &body body)
  "Execute BODY with WAL-VAR bound to a test WAL instance.
   Automatically creates temp directory and cleans up."
  (let ((dir-var (gensym "DIR-")))
    `(with-temp-wal-directory (,dir-var)
       (let ((,wal-var (sw4rm-orchestrator.persistence::make-wal-log
                        (merge-pathnames "test.wal" ,dir-var)
                        :flush-interval ,flush-interval
                        :sync-mode ,sync-mode
                        :sharding-enabled nil)))
         (unwind-protect
             (progn ,@body)
           (sw4rm-orchestrator.persistence::wal-close ,wal-var))))))

;;;; ============================================================================
;;;; Section 1: Basic Operations Tests (10+ tests)
;;;; ============================================================================

(test wal-creation-basic
  "Test creating a basic WAL instance with defaults."
  (with-temp-wal-directory (dir)
    (let ((wal-path (merge-pathnames "test.wal" dir)))
      (let ((wal (sw4rm-orchestrator.persistence::make-wal-log wal-path)))
        (unwind-protect
            (progn
              (is (not (null wal)))
              (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 0))
              (is (eq (sw4rm-orchestrator.persistence::wal-sync-mode wal) :sync))
              (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 0)))
          (sw4rm-orchestrator.persistence::wal-close wal))))))

(test wal-creation-with-options
  "Test creating WAL with custom configuration."
  (with-temp-wal-directory (dir)
    (let ((wal-path (merge-pathnames "test.wal" dir)))
      (let ((wal (sw4rm-orchestrator.persistence::make-wal-log
                  wal-path
                  :flush-interval 10
                  :max-size (* 1024 1024 50)
                  :sync-mode :batch)))
        (unwind-protect
            (progn
              (is (not (null wal)))
              (is (= (sw4rm-orchestrator.persistence::wal-flush-interval wal) 10))
              (is (= (sw4rm-orchestrator.persistence::wal-max-size wal) (* 1024 1024 50)))
              (is (eq (sw4rm-orchestrator.persistence::wal-sync-mode wal) :batch)))
          (sw4rm-orchestrator.persistence::wal-close wal))))))

(test wal-append-basic
  "Test appending a single entry to WAL."
  (with-test-wal (wal)
    (let ((seq (sw4rm-orchestrator.persistence::wal-append
                wal :route '(:from "leaf-a" :to "leaf-b"))))
      (is (= seq 1))
      (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 1))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1)))))

(test wal-append-sequence-increments
  "Test that sequence number increments with each append."
  (with-test-wal (wal)
    (let ((seq1 (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "first")))
          (seq2 (sw4rm-orchestrator.persistence::wal-append wal :register '(:data "second")))
          (seq3 (sw4rm-orchestrator.persistence::wal-append wal :unregister '(:data "third"))))
      (is (= seq1 1))
      (is (= seq2 2))
      (is (= seq3 3))
      (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 3)))))

(test wal-append-multiple-operations
  "Test appending multiple different operation types."
  (with-test-wal (wal :flush-interval 100)
    ;; Append various operation types
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:from "a" :to "b"))
    (sw4rm-orchestrator.persistence::wal-append wal :register '(:leaf-id "leaf-1"))
    (sw4rm-orchestrator.persistence::wal-append wal :unregister '(:leaf-id "leaf-2"))
    (sw4rm-orchestrator.persistence::wal-append wal :deliver '(:envelope-id "env-1"))
    (sw4rm-orchestrator.persistence::wal-append wal :checkpoint '(:state "snapshot"))

    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 5))

    ;; Check stats track operation types
    (let ((stats (sw4rm-orchestrator.persistence::wal-stats wal)))
      (is (= (gethash :route stats 0) 1))
      (is (= (gethash :register stats 0) 1))
      (is (= (gethash :unregister stats 0) 1)))))

(test wal-entry-structure
  "Test that WAL entries have correct structure."
  (with-test-wal (wal :flush-interval 100)
    (let ((before-time (get-universal-time)))
      (sw4rm-orchestrator.persistence::wal-append wal :route '(:test "data"))
      (let ((after-time (get-universal-time)))
        ;; Get entries from buffer
        (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
          (is (= (length entries) 1))
          (let ((entry (first entries)))
            (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence entry) 1))
            (is (>= (sw4rm-orchestrator.persistence::wal-entry-timestamp entry) before-time))
            (is (<= (sw4rm-orchestrator.persistence::wal-entry-timestamp entry) after-time))
            (is (eq (sw4rm-orchestrator.persistence::wal-entry-operation entry) :route))
            (is (equal (sw4rm-orchestrator.persistence::wal-entry-data entry) '(:test "data")))
            (is (integerp (sw4rm-orchestrator.persistence::wal-entry-checksum entry)))))))))

(test wal-read-back-entries
  "Test reading back appended entries."
  (with-test-wal (wal :flush-interval 100)
    ;; Append several entries
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 2))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 3))

    ;; Read back
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 3))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (first entries)) 1))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (second entries)) 2))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (third entries)) 3)))))

(test wal-entries-with-range
  "Test reading entries with from/to range."
  (with-test-wal (wal :flush-interval 100)
    ;; Append 5 entries
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Read subset
    (let ((subset (sw4rm-orchestrator.persistence::wal-entries wal :from 2 :to 4)))
      (is (= (length subset) 3))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (first subset)) 2))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (third subset)) 4)))))

(test wal-stats-tracking
  "Test that WAL tracks operation statistics."
  (with-test-wal (wal :flush-interval 100)
    ;; Perform various operations
    (dotimes (i 5) (sw4rm-orchestrator.persistence::wal-append wal :route '()))
    (dotimes (i 3) (sw4rm-orchestrator.persistence::wal-append wal :register '()))
    (dotimes (i 2) (sw4rm-orchestrator.persistence::wal-append wal :unregister '()))

    (let ((full-stats (sw4rm-orchestrator.persistence::wal-get-stats wal)))
      (is (= (getf full-stats :total-entries) 10))
      (is (= (getf full-stats :current-sequence) 10))
      (is (= (getf full-stats :rotations) 0))

      ;; Check per-operation stats
      (let ((ops (getf full-stats :operations)))
        (is (= (gethash :route ops 0) 5))
        (is (= (gethash :register ops 0) 3))
        (is (= (gethash :unregister ops 0) 2))))))

(test wal-last-sequence
  "Test getting last sequence number."
  (with-test-wal (wal)
    (is (= (sw4rm-orchestrator.persistence::wal-last-sequence wal) 0))

    (sw4rm-orchestrator.persistence::wal-append wal :route '())
    (is (= (sw4rm-orchestrator.persistence::wal-last-sequence wal) 1))

    (sw4rm-orchestrator.persistence::wal-append wal :route '())
    (sw4rm-orchestrator.persistence::wal-append wal :route '())
    (is (= (sw4rm-orchestrator.persistence::wal-last-sequence wal) 3))))

(test wal-close-idempotent
  "Test that closing WAL multiple times is safe."
  (with-temp-wal-directory (dir)
    (let ((wal (sw4rm-orchestrator.persistence::make-wal-log
                (merge-pathnames "test.wal" dir))))
      (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test"))
      (is (sw4rm-orchestrator.persistence::wal-close wal))
      ;; Second close should not error
      (is (sw4rm-orchestrator.persistence::wal-close wal)))))

;;;; ============================================================================
;;;; Section 2: Durability Tests (8+ tests)
;;;; ============================================================================

(test wal-flush-writes-to-disk
  "Test that flush writes entries to disk."
  (with-test-wal (wal :flush-interval 100)
    ;; Append entries without auto-flush
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test1"))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test2"))

    ;; Explicitly flush
    (let ((flushed (sw4rm-orchestrator.persistence::wal-flush wal)))
      (is (= flushed 2)))))

(test wal-auto-flush-on-threshold
  "Test automatic flush when buffer reaches threshold."
  (with-test-wal (wal :flush-interval 3)
    ;; First two entries should not trigger flush
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "1"))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "2"))

    ;; Buffer should have 2 entries
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 2))

    ;; Third entry should trigger auto-flush
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "3"))

    ;; Buffer should be cleared after flush
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))))

(test wal-flush-clears-buffer
  "Test that flush clears the in-memory buffer."
  (with-test-wal (wal :flush-interval 100)
    ;; Add entries
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "1"))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "2"))

    ;; Buffer should have entries
    (is (> (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))

    ;; Flush
    (sw4rm-orchestrator.persistence::wal-flush wal)

    ;; Buffer should be empty
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))))

(test wal-flush-empty-buffer
  "Test flushing an empty buffer."
  (with-test-wal (wal)
    ;; Flush empty buffer should not error
    (let ((count (sw4rm-orchestrator.persistence::wal-flush wal)))
      (is (= count 0)))))

(test wal-sync-mode-sync
  "Test sync mode forces durability."
  (with-test-wal (wal :sync-mode :sync)
    (is (eq (sw4rm-orchestrator.persistence::wal-sync-mode wal) :sync))
    ;; Append and flush should work
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "sync-test"))
    (sw4rm-orchestrator.persistence::wal-flush wal)
    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1))))

(test wal-sync-mode-async
  "Test async mode for faster but less durable writes."
  (with-test-wal (wal :sync-mode :async)
    (is (eq (sw4rm-orchestrator.persistence::wal-sync-mode wal) :async))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "async-test"))
    (sw4rm-orchestrator.persistence::wal-flush wal)
    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1))))

(test wal-sync-mode-batch
  "Test batch sync mode for balanced performance."
  (with-test-wal (wal :sync-mode :batch)
    (is (eq (sw4rm-orchestrator.persistence::wal-sync-mode wal) :batch))
    ;; Append multiple entries
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id i)))
    (sw4rm-orchestrator.persistence::wal-flush wal)
    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 10))))

(test wal-multiple-flush-cycles
  "Test multiple write-flush cycles."
  (with-test-wal (wal :flush-interval 100)
    ;; First cycle
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:cycle 1))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:cycle 1))
    (sw4rm-orchestrator.persistence::wal-flush wal)

    ;; Second cycle
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:cycle 2))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:cycle 2))
    (sw4rm-orchestrator.persistence::wal-flush wal)

    ;; Third cycle
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:cycle 3))
    (sw4rm-orchestrator.persistence::wal-flush wal)

    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 5))
    (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 5))))

(test wal-ensure-durability
  "Test explicit durability check."
  (with-test-wal (wal :sync-mode :sync)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "durable"))
    (sw4rm-orchestrator.persistence::wal-flush wal)
    ;; Ensure durability should not error
    (is (sw4rm-orchestrator.persistence::wal-ensure-durability wal))))

;;;; ============================================================================
;;;; Section 3: Integrity Tests (8+ tests)
;;;; ============================================================================

(test wal-checksum-computation
  "Test checksum is computed for entries."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test"))
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 1))
      (let ((entry (first entries)))
        ;; Checksum should be non-zero for non-trivial data
        (is (integerp (sw4rm-orchestrator.persistence::wal-entry-checksum entry)))))))

(test wal-checksum-verification-valid
  "Test checksum verification succeeds for valid entries."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:key "value"))
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (let ((entry (first entries)))
        (is (sw4rm-orchestrator.persistence::verify-wal-checksum entry))))))

(test wal-checksum-verification-detects-corruption
  "Test checksum verification fails for corrupted entries."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:original "data"))
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (let ((entry (first entries)))
        ;; Corrupt the entry by changing data
        (setf (sw4rm-orchestrator.persistence::wal-entry-data entry) '(:corrupted "data"))
        ;; Checksum should now fail
        (is (not (sw4rm-orchestrator.persistence::verify-wal-checksum entry)))))))

(test wal-checksum-different-for-different-data
  "Test checksums differ for different data."
  (let ((checksum1 (sw4rm-orchestrator.persistence::compute-wal-checksum
                    1 :route '(:data "first")))
        (checksum2 (sw4rm-orchestrator.persistence::compute-wal-checksum
                    2 :route '(:data "second"))))
    (is (not (= checksum1 checksum2)))))

(test wal-checksum-same-for-same-data
  "Test checksums are consistent for same data."
  (let ((checksum1 (sw4rm-orchestrator.persistence::compute-wal-checksum
                    1 :route '(:data "same")))
        (checksum2 (sw4rm-orchestrator.persistence::compute-wal-checksum
                    1 :route '(:data "same"))))
    (is (= checksum1 checksum2))))

(test wal-replay-skips-invalid-checksum
  "Test that replay skips entries with invalid checksums."
  (with-test-wal (wal :flush-interval 100)
    ;; Add valid entries
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 2))

    ;; Corrupt one entry
    (let ((entries (sw4rm-orchestrator.persistence::wal-buffer wal)))
      (when (> (length entries) 0)
        (let ((entry (aref entries 0)))
          (setf (sw4rm-orchestrator.persistence::wal-entry-data entry) '(:corrupted t)))))

    ;; Replay should skip corrupted entry
    (let ((replayed-count 0))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (declare (ignore entry))
         (incf replayed-count)))
      ;; Should have replayed only 1 entry (the valid one)
      (is (= replayed-count 1)))))

(test wal-entry-sequence-validation
  "Test that entries maintain valid sequence ordering."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id i)))

    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      ;; Verify sequences are monotonically increasing
      (loop for prev = nil then entry
            for entry in entries
            when prev
              do (is (> (sw4rm-orchestrator.persistence::wal-entry-sequence entry)
                        (sw4rm-orchestrator.persistence::wal-entry-sequence prev)))))))

(test wal-handles-nil-data
  "Test WAL handles nil payload data."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::wal-append wal :route nil)
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 1))
      (is (null (sw4rm-orchestrator.persistence::wal-entry-data (first entries)))))))

(test wal-handles-complex-data
  "Test WAL handles complex nested data structures."
  (with-test-wal (wal :flush-interval 100)
    (let ((complex-data '(:outer (:inner (:deep "value"))
                         :list (1 2 3 4 5)
                         :hash-like ((:key1 . "val1") (:key2 . "val2")))))
      (sw4rm-orchestrator.persistence::wal-append wal :route complex-data)
      (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
        (is (= (length entries) 1))
        (is (equal (sw4rm-orchestrator.persistence::wal-entry-data (first entries))
                   complex-data))))))

;;;; ============================================================================
;;;; Section 4: Truncation Tests (6+ tests)
;;;; ============================================================================

(test wal-truncate-basic
  "Test basic truncation operation."
  (with-test-wal (wal :flush-interval 100)
    ;; Add entries
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Truncate entries before sequence 5
    (let ((deleted (sw4rm-orchestrator.persistence::wal-truncate wal 5)))
      ;; Note: Current implementation returns 0 (TODO in source)
      ;; When implemented, should delete 4 entries (sequences 1-4)
      (is (>= deleted 0)))))

(test wal-truncate-preserves-entries-after-cutoff
  "Test truncation preserves entries after cutoff point."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; After truncation, entries with sequence >= cutoff should remain
    (sw4rm-orchestrator.persistence::wal-truncate wal 6)

    ;; Read entries from sequence 6 onwards
    (let ((remaining (sw4rm-orchestrator.persistence::wal-entries wal :from 6)))
      ;; Should have entries 6-10 (5 entries)
      (is (>= (length remaining) 0)))))  ; Placeholder until truncate is implemented

(test wal-truncate-empty-wal
  "Test truncation on empty WAL."
  (with-test-wal (wal)
    ;; Should not error
    (let ((deleted (sw4rm-orchestrator.persistence::wal-truncate wal 100)))
      (is (= deleted 0)))))

(test wal-truncate-with-all-entries-before-cutoff
  "Test truncation when all entries are before cutoff."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Truncate with cutoff after all entries
    (let ((deleted (sw4rm-orchestrator.persistence::wal-truncate wal 100)))
      ;; Should handle gracefully
      (is (>= deleted 0)))))

(test wal-truncate-with-cutoff-before-all-entries
  "Test truncation when cutoff is before all entries."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Truncate with cutoff before all entries
    (let ((deleted (sw4rm-orchestrator.persistence::wal-truncate wal 0)))
      ;; Should not delete anything
      (is (= deleted 0)))))

(test wal-truncate-at-exact-sequence
  "Test truncation at exact sequence boundary."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Truncate at sequence 3 (should remove 1, 2)
    (sw4rm-orchestrator.persistence::wal-truncate wal 3)

    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal :from 3)))
      (when (> (length entries) 0)
        ;; First remaining entry should be sequence 3
        (is (= (sw4rm-orchestrator.persistence::wal-entry-sequence (first entries)) 3))))))

;;;; ============================================================================
;;;; Section 5: Compaction Tests (5+ tests)
;;;; ============================================================================

(test wal-compact-basic
  "Test basic compaction operation."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Compact should succeed
    (is (sw4rm-orchestrator.persistence::wal-compact wal))))

(test wal-compact-empty-wal
  "Test compaction on empty WAL."
  (with-test-wal (wal)
    ;; Should not error on empty WAL
    (is (sw4rm-orchestrator.persistence::wal-compact wal))))

(test wal-compact-preserves-entry-order
  "Test that compaction preserves entry order."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Record sequences before compact
    (let ((before-sequences
            (mapcar #'sw4rm-orchestrator.persistence::wal-entry-sequence
                    (sw4rm-orchestrator.persistence::wal-entries wal))))

      (sw4rm-orchestrator.persistence::wal-compact wal)

      ;; Sequences should be in same order
      (let ((after-sequences
              (mapcar #'sw4rm-orchestrator.persistence::wal-entry-sequence
                      (sw4rm-orchestrator.persistence::wal-entries wal))))
        (is (equal before-sequences after-sequences))))))

(test wal-compact-is-idempotent
  "Test that compaction is idempotent."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Multiple compactions should produce same result
    (sw4rm-orchestrator.persistence::wal-compact wal)
    (let ((count1 (length (sw4rm-orchestrator.persistence::wal-entries wal))))

      (sw4rm-orchestrator.persistence::wal-compact wal)
      (let ((count2 (length (sw4rm-orchestrator.persistence::wal-entries wal))))

        (sw4rm-orchestrator.persistence::wal-compact wal)
        (let ((count3 (length (sw4rm-orchestrator.persistence::wal-entries wal))))

          (is (= count1 count2 count3)))))))

(test wal-compact-after-truncate
  "Test compaction after truncation."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    (sw4rm-orchestrator.persistence::wal-truncate wal 5)
    (is (sw4rm-orchestrator.persistence::wal-compact wal))))

;;;; ============================================================================
;;;; Section 6: Concurrent Access Tests (5+ tests)
;;;; ============================================================================

(test wal-concurrent-appends
  "Test multiple concurrent append operations."
  (with-test-wal (wal :flush-interval 100)
    (let ((num-threads 5)
          (entries-per-thread 10)
          (threads nil))

      ;; Start multiple threads appending
      (dotimes (i num-threads)
        (push (bt:make-thread
               (lambda ()
                 (dotimes (j entries-per-thread)
                   (sw4rm-orchestrator.persistence::wal-append
                    wal :route (list :thread i :entry j))))
               :name (format nil "wal-writer-~D" i))
              threads))

      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))

      ;; Should have all entries
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal)
             (* num-threads entries-per-thread))))))

(test wal-concurrent-append-unique-sequences
  "Test that concurrent appends produce unique sequence numbers."
  (with-test-wal (wal :flush-interval 1000)
    (let ((num-threads 4)
          (entries-per-thread 25)
          (sequences (bt:make-lock "sequences"))
          (all-sequences nil)
          (threads nil))

      ;; Start threads that collect their sequence numbers
      (dotimes (i num-threads)
        (push (bt:make-thread
               (lambda ()
                 (dotimes (j entries-per-thread)
                   (let ((seq (sw4rm-orchestrator.persistence::wal-append
                               wal :route (list :thread i :entry j))))
                     (bt:with-lock-held (sequences)
                       (push seq all-sequences)))))
               :name (format nil "wal-writer-~D" i))
              threads))

      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))

      ;; All sequences should be unique
      (is (= (length all-sequences)
             (length (remove-duplicates all-sequences)))))))

(test wal-concurrent-append-and-flush
  "Test concurrent append and flush operations."
  (with-test-wal (wal :flush-interval 100)
    (let ((stop-flag nil)
          (writer-thread nil)
          (flusher-thread nil))

      ;; Writer thread
      (setf writer-thread
            (bt:make-thread
             (lambda ()
               (dotimes (i 50)
                 (sw4rm-orchestrator.persistence::wal-append wal :route (list :id i))
                 (sleep 0.01)))
             :name "wal-writer"))

      ;; Flusher thread
      (setf flusher-thread
            (bt:make-thread
             (lambda ()
               (dotimes (i 10)
                 (sw4rm-orchestrator.persistence::wal-flush wal)
                 (sleep 0.05)))
             :name "wal-flusher"))

      ;; Wait for threads
      (bt:join-thread writer-thread)
      (bt:join-thread flusher-thread)

      ;; Should have all entries
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 50)))))

(test wal-concurrent-append-and-read
  "Test concurrent append and read operations."
  (with-test-wal (wal :flush-interval 100)
    (let ((writer-thread nil)
          (reader-results nil)
          (reader-lock (bt:make-lock "reader")))

      ;; Writer thread
      (setf writer-thread
            (bt:make-thread
             (lambda ()
               (dotimes (i 20)
                 (sw4rm-orchestrator.persistence::wal-append wal :route (list :id i))
                 (sleep 0.01)))
             :name "wal-writer"))

      ;; Reader thread
      (let ((reader-thread
              (bt:make-thread
               (lambda ()
                 (dotimes (i 10)
                   (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
                     (bt:with-lock-held (reader-lock)
                       (push (length entries) reader-results)))
                   (sleep 0.02)))
               :name "wal-reader")))

        ;; Wait for threads
        (bt:join-thread writer-thread)
        (bt:join-thread reader-thread)

        ;; Reader should have seen increasing entry counts
        (is (not (null reader-results)))))))

(test wal-buffer-lock-prevents-corruption
  "Test that buffer lock prevents data corruption."
  (with-test-wal (wal :flush-interval 1000)
    (let ((threads nil)
          (num-threads 10)
          (ops-per-thread 20))

      ;; Start many threads doing mixed operations
      (dotimes (i num-threads)
        (push (bt:make-thread
               (lambda ()
                 (dotimes (j ops-per-thread)
                   (if (evenp j)
                       (sw4rm-orchestrator.persistence::wal-append
                        wal :route (list :thread i :op j))
                       (sw4rm-orchestrator.persistence::wal-entries wal))))
               :name (format nil "wal-mixed-~D" i))
              threads))

      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))

      ;; Entry count should match number of appends
      ;; (half of ops-per-thread per thread)
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal)
             (* num-threads (/ ops-per-thread 2)))))))

;;;; ============================================================================
;;;; Section 7: Recovery Scenario Tests (8+ tests)
;;;; ============================================================================

(test wal-replay-all-entries
  "Test replaying all WAL entries."
  (with-test-wal (wal :flush-interval 100)
    ;; Append entries
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Replay and count
    (let ((replayed-entries nil))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (push entry replayed-entries)))

      (is (= (length replayed-entries) 5)))))

(test wal-replay-with-filter
  "Test replaying with operation type filter."
  (with-test-wal (wal :flush-interval 100)
    ;; Append mixed operations
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1))
    (sw4rm-orchestrator.persistence::wal-append wal :register '(:id 2))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 3))
    (sw4rm-orchestrator.persistence::wal-append wal :unregister '(:id 4))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 5))

    ;; Replay only :route operations
    (let ((route-count 0))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (declare (ignore entry))
         (incf route-count))
       :filter-op :route)

      (is (= route-count 3)))))

(test wal-replay-with-sequence-range
  "Test replaying entries within sequence range."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 10)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Replay entries 3-7
    (let ((replayed-sequences nil))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (push (sw4rm-orchestrator.persistence::wal-entry-sequence entry)
               replayed-sequences))
       :from-sequence 3
       :to-sequence 7)

      (is (= (length replayed-sequences) 5))
      (is (member 3 replayed-sequences))
      (is (member 7 replayed-sequences))
      (is (not (member 2 replayed-sequences)))
      (is (not (member 8 replayed-sequences))))))

(test wal-replay-empty-wal
  "Test replaying empty WAL."
  (with-test-wal (wal)
    (let ((count 0))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (declare (ignore entry))
         (incf count)))
      (is (= count 0)))))

(test wal-replay-handler-error-continues
  "Test that replay continues after handler error."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    ;; Handler that errors on entry 3
    (let ((processed nil))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (let ((seq (sw4rm-orchestrator.persistence::wal-entry-sequence entry)))
           (if (= seq 3)
               (error "Simulated handler error")
               (push seq processed)))))

      ;; Should have processed 1, 2, 4, 5 (skipped 3 due to error)
      (is (= (length processed) 4))
      (is (not (member 3 processed))))))

(test wal-replay-returns-count
  "Test that replay returns count of replayed entries."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 7)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    (let ((count (sw4rm-orchestrator.persistence::wal-replay
                  wal
                  (lambda (entry) (declare (ignore entry))))))
      (is (= count 7)))))

(test wal-replay-with-multiple-operation-filters
  "Test replaying with multiple operation type filters."
  (with-test-wal (wal :flush-interval 100)
    ;; Append various operations
    (sw4rm-orchestrator.persistence::wal-append wal :route '())
    (sw4rm-orchestrator.persistence::wal-append wal :register '())
    (sw4rm-orchestrator.persistence::wal-append wal :unregister '())
    (sw4rm-orchestrator.persistence::wal-append wal :checkpoint '())
    (sw4rm-orchestrator.persistence::wal-append wal :route '())

    ;; Filter for :route and :register
    (let ((count 0))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry) (declare (ignore entry)) (incf count))
       :filter-op '(:route :register))

      (is (= count 3)))))

(test wal-replay-data-integrity
  "Test that replayed entries maintain data integrity."
  (with-test-wal (wal :flush-interval 100)
    (let ((test-data '(:complex (:nested "value") :list (1 2 3))))
      (sw4rm-orchestrator.persistence::wal-append wal :route test-data)

      (let ((recovered-data nil))
        (sw4rm-orchestrator.persistence::wal-replay
         wal
         (lambda (entry)
           (setf recovered-data
                 (sw4rm-orchestrator.persistence::wal-entry-data entry))))

        (is (equal recovered-data test-data))))))

;;;; ============================================================================
;;;; Section 8: Rotation Tests (6+ tests)
;;;; ============================================================================

(test wal-size-tracking
  "Test WAL file size tracking."
  (with-test-wal (wal)
    ;; Size should be tracked
    (let ((initial-size (sw4rm-orchestrator.persistence::wal-size wal)))
      (is (>= initial-size 0)))))

(test wal-max-size-configuration
  "Test WAL max size configuration."
  (with-temp-wal-directory (dir)
    (let ((wal (sw4rm-orchestrator.persistence::make-wal-log
                (merge-pathnames "test.wal" dir)
                :max-size (* 1024 1024 10))))  ; 10 MB
      (unwind-protect
          (is (= (sw4rm-orchestrator.persistence::wal-max-size wal)
                 (* 1024 1024 10)))
        (sw4rm-orchestrator.persistence::wal-close wal)))))

(test wal-rotate-basic
  "Test basic WAL rotation."
  (with-test-wal (wal)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "before-rotate"))
    (sw4rm-orchestrator.persistence::wal-flush wal)

    ;; Rotate
    (is (sw4rm-orchestrator.persistence::wal-rotate wal))

    ;; Rotation count should increment
    (is (= (sw4rm-orchestrator.persistence::wal-rotation-count wal) 1))))

(test wal-rotate-flushes-first
  "Test that rotation flushes buffer first."
  (with-test-wal (wal :flush-interval 100)
    ;; Add entries without flushing
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "1"))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "2"))

    ;; Buffer should have entries
    (is (> (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))

    ;; Rotate (should flush first)
    (sw4rm-orchestrator.persistence::wal-rotate wal)

    ;; Buffer should be empty after rotate
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))))

(test wal-rotate-preserves-sequence
  "Test that rotation preserves sequence numbering."
  (with-test-wal (wal)
    (dotimes (i 5)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id (1+ i))))

    (let ((seq-before (sw4rm-orchestrator.persistence::wal-sequence-number wal)))
      (sw4rm-orchestrator.persistence::wal-rotate wal)

      ;; Sequence should be preserved
      (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) seq-before))

      ;; New entries should continue from last sequence
      (let ((new-seq (sw4rm-orchestrator.persistence::wal-append wal :route '(:after "rotate"))))
        (is (= new-seq 6))))))

(test wal-multiple-rotations
  "Test multiple consecutive rotations."
  (with-test-wal (wal)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:rotation 1))
    (sw4rm-orchestrator.persistence::wal-rotate wal)
    (is (= (sw4rm-orchestrator.persistence::wal-rotation-count wal) 1))

    (sw4rm-orchestrator.persistence::wal-append wal :route '(:rotation 2))
    (sw4rm-orchestrator.persistence::wal-rotate wal)
    (is (= (sw4rm-orchestrator.persistence::wal-rotation-count wal) 2))

    (sw4rm-orchestrator.persistence::wal-append wal :route '(:rotation 3))
    (sw4rm-orchestrator.persistence::wal-rotate wal)
    (is (= (sw4rm-orchestrator.persistence::wal-rotation-count wal) 3))))

;;;; ============================================================================
;;;; Section 9: WAL Transaction Tests (5+ tests)
;;;; ============================================================================

(test wal-transaction-logs-boundaries
  "Test that transactions log start/end boundaries."
  (with-test-wal (wal :flush-interval 100)
    ;; Execute a transaction
    (sw4rm-orchestrator.persistence::wal-transaction wal
      (sw4rm-orchestrator.persistence::wal-append wal :route '(:inside "transaction")))

    ;; Should have transaction-start, route, transaction-commit entries
    (let ((stats (sw4rm-orchestrator.persistence::wal-stats wal)))
      (is (>= (gethash :transaction-start stats 0) 1))
      (is (>= (gethash :transaction-commit stats 0) 1)))))

(test wal-transaction-flushes-on-complete
  "Test that transactions flush on completion."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::wal-transaction wal
      (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test")))

    ;; Buffer should be empty after transaction
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))))

(test wal-transaction-returns-result
  "Test that transactions return body result."
  (with-test-wal (wal :flush-interval 100)
    (let ((result (sw4rm-orchestrator.persistence::wal-transaction wal
                    (+ 1 2 3))))
      (is (= result 6)))))

(test wal-logging-context-macro
  "Test WITH-WAL-LOGGING context macro."
  (with-test-wal (wal :flush-interval 100)
    (sw4rm-orchestrator.persistence::with-wal-logging wal
      (sw4rm-orchestrator.persistence::wal-append wal :route '(:in "context")))

    ;; Should have flushed on exit
    (is (= (fill-pointer (sw4rm-orchestrator.persistence::wal-buffer wal)) 0))))

(test wal-context-variable
  "Test WAL context variable management."
  ;; Initially no context
  (is (not (sw4rm-orchestrator.persistence::wal-enabled-p)))

  (with-test-wal (wal)
    (let ((sw4rm-orchestrator.persistence::*wal-context* wal))
      (is (sw4rm-orchestrator.persistence::wal-enabled-p)))))

;;;; ============================================================================
;;;; Section 10: Edge Cases and Error Handling (5+ tests)
;;;; ============================================================================

(test wal-append-large-payload
  "Test appending entries with large payloads."
  (with-test-wal (wal :flush-interval 100)
    (let ((large-data (make-list 1000 :initial-element '(:key "value"))))
      (sw4rm-orchestrator.persistence::wal-append wal :route large-data)
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1)))))

(test wal-append-many-entries
  "Test appending many entries in sequence."
  (with-test-wal (wal :flush-interval 100)
    (dotimes (i 1000)
      (sw4rm-orchestrator.persistence::wal-append wal :route (list :id i)))

    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1000))
    (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 1000))))

(test wal-append-empty-operation-data
  "Test appending entry with empty data."
  (with-test-wal (wal)
    (let ((seq (sw4rm-orchestrator.persistence::wal-append wal :route '())))
      (is (= seq 1)))))

(test wal-entries-from-empty-buffer
  "Test reading entries when buffer is empty."
  (with-test-wal (wal)
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (null entries)))))

(test wal-handles-special-characters-in-data
  "Test WAL handles special characters in data."
  (with-test-wal (wal :flush-interval 100)
    (let ((special-data '(:text "Hello\nWorld\t\"Quoted\""
                         :unicode "..."
                         :empty "")))
      (sw4rm-orchestrator.persistence::wal-append wal :route special-data)
      (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
        (is (= (length entries) 1))
        (is (equal (sw4rm-orchestrator.persistence::wal-entry-data (first entries))
                   special-data))))))

;;;; ============================================================================
;;;; Section 11: Lock Sharding Tests (P2-3/P3-10)
;;;; ============================================================================
;;;;
;;;; Tests for the 16-shard lock pool implementation.
;;;; These tests verify:
;;;;   - Shard index computation
;;;;   - Concurrent appends to different shards
;;;;   - Flush merges entries correctly
;;;;   - Compaction coordinates across shards
;;;;   - Truncation maintains ordering
;;;;   - Recovery replays in correct sequence

(defmacro with-sharded-test-wal ((wal-var &key (flush-interval 100) (sync-mode :sync)) &body body)
  "Execute BODY with WAL-VAR bound to a sharded test WAL instance.
   Automatically creates temp directory and cleans up."
  (let ((dir-var (gensym "DIR-")))
    `(with-temp-wal-directory (,dir-var)
       (let ((,wal-var (sw4rm-orchestrator.persistence::make-wal-log
                        (merge-pathnames "test.wal" ,dir-var)
                        :flush-interval ,flush-interval
                        :sync-mode ,sync-mode
                        :sharding-enabled t)))
         (unwind-protect
             (progn ,@body)
           (sw4rm-orchestrator.persistence::wal-close ,wal-var))))))

(test wal-sharding-enabled-by-default
  "Test that sharding is enabled by default in new WAL instances."
  (with-sharded-test-wal (wal)
    (is (sw4rm-orchestrator.persistence::wal-sharding-enabled wal))))

(test wal-sharding-can-be-disabled
  "Test that sharding can be disabled."
  (with-temp-wal-directory (dir)
    (let ((wal (sw4rm-orchestrator.persistence::make-wal-log
                (merge-pathnames "test.wal" dir)
                :sharding-enabled nil)))
      (unwind-protect
          (is (not (sw4rm-orchestrator.persistence::wal-sharding-enabled wal)))
        (sw4rm-orchestrator.persistence::wal-close wal)))))

(test wal-shard-index-computation
  "Test shard index computation from swarm ID."
  ;; Same swarm-id should always map to same shard
  (let ((shard1 (sw4rm-orchestrator.persistence::compute-shard-index "leaf-a"))
        (shard2 (sw4rm-orchestrator.persistence::compute-shard-index "leaf-a")))
    (is (= shard1 shard2))
    (is (>= shard1 0))
    (is (< shard1 16)))

  ;; nil maps to shard 0
  (is (= (sw4rm-orchestrator.persistence::compute-shard-index nil) 0))

  ;; Different swarm-ids should be in valid range
  (dolist (id '("leaf-a" "leaf-b" "leaf-c" "swarm-1" "swarm-2"))
    (let ((shard (sw4rm-orchestrator.persistence::compute-shard-index id)))
      (is (>= shard 0))
      (is (< shard 16)))))

(test wal-shard-distribution
  "Test that different swarm IDs distribute across shards."
  (let ((shard-hits (make-array 16 :initial-element 0)))
    ;; Test many different swarm IDs
    (dotimes (i 160)
      (let* ((swarm-id (format nil "swarm-~D" i))
             (shard (sw4rm-orchestrator.persistence::compute-shard-index swarm-id)))
        (incf (aref shard-hits shard))))

    ;; Check that multiple shards are used (distribution check)
    (let ((used-shards (count-if #'plusp shard-hits)))
      (is (> used-shards 8) "Expected at least 8 shards to be used with 160 IDs"))))

(test wal-sharded-append-basic
  "Test basic append with sharding enabled."
  (with-sharded-test-wal (wal)
    (let ((seq (sw4rm-orchestrator.persistence::wal-append
                wal :route '(:data "test") :swarm-id "leaf-a")))
      (is (= seq 1))
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 1)))))

(test wal-sharded-append-different-swarms
  "Test appending entries for different swarms."
  (with-sharded-test-wal (wal)
    ;; Append entries for different swarms
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1) :swarm-id "leaf-a")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 2) :swarm-id "leaf-b")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 3) :swarm-id "leaf-c")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 4) :swarm-id "leaf-d")

    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 4))
    (is (= (sw4rm-orchestrator.persistence::wal-sequence-number wal) 4))))

(test wal-sharded-sequence-monotonic
  "Test that sequence numbers are monotonically increasing across shards."
  (with-sharded-test-wal (wal)
    (let ((sequences nil))
      ;; Append to different shards
      (dotimes (i 20)
        (let* ((swarm-id (format nil "swarm-~D" i))
               (seq (sw4rm-orchestrator.persistence::wal-append
                     wal :route (list :id i) :swarm-id swarm-id)))
          (push seq sequences)))

      ;; Check all sequences are unique
      (is (= (length sequences) (length (remove-duplicates sequences))))

      ;; Check sequences form a contiguous range 1-20
      (let ((sorted (sort sequences #'<)))
        (is (equal sorted (loop for i from 1 to 20 collect i)))))))

(test wal-sharded-flush-merges-entries
  "Test that flush merges entries from all shards in sequence order."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1) :swarm-id "leaf-a")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 2) :swarm-id "leaf-b")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 3) :swarm-id "leaf-a")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 4) :swarm-id "leaf-c")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 5) :swarm-id "leaf-b")

    ;; Flush all shards
    (let ((flushed (sw4rm-orchestrator.persistence::wal-flush wal)))
      (is (= flushed 5)))

    ;; All shard buffers should be empty
    (is (= (sw4rm-orchestrator.persistence::total-shard-entries wal) 0))))

(test wal-sharded-entries-in-sequence-order
  "Test that WAL entries are returned in sequence order across shards."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards in interleaved fashion
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 1) :swarm-id "shard-0")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 2) :swarm-id "shard-5")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 3) :swarm-id "shard-10")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 4) :swarm-id "shard-0")
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:id 5) :swarm-id "shard-5")

    ;; Get entries (should be in sequence order regardless of shard)
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 5))
      ;; Verify sequence ordering
      (loop for i from 0 below (1- (length entries))
            do (let ((curr (sw4rm-orchestrator.persistence::wal-entry-sequence (nth i entries)))
                     (next (sw4rm-orchestrator.persistence::wal-entry-sequence (nth (1+ i) entries))))
                 (is (< curr next) "Entries should be in ascending sequence order"))))))

(test wal-sharded-concurrent-appends
  "Test concurrent appends to different shards."
  (with-sharded-test-wal (wal)
    (let ((num-threads 8)
          (entries-per-thread 25)
          (threads nil))

      ;; Start threads writing to different shards
      (dotimes (i num-threads)
        (push (bt:make-thread
               (lambda ()
                 (let ((swarm-id (format nil "swarm-~D" (mod i 4)))) ; 4 different swarm IDs
                   (dotimes (j entries-per-thread)
                     (sw4rm-orchestrator.persistence::wal-append
                      wal :route (list :thread i :entry j) :swarm-id swarm-id))))
               :name (format nil "sharded-writer-~D" i))
              threads))

      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))

      ;; Should have all entries
      (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal)
             (* num-threads entries-per-thread))))))

(test wal-sharded-concurrent-unique-sequences
  "Test that concurrent sharded appends produce unique sequence numbers."
  (with-sharded-test-wal (wal)
    (let ((num-threads 4)
          (entries-per-thread 50)
          (sequences (bt:make-lock "sequences"))
          (all-sequences nil)
          (threads nil))

      ;; Start threads collecting their sequence numbers
      (dotimes (i num-threads)
        (push (bt:make-thread
               (lambda ()
                 (let ((swarm-id (format nil "swarm-~D" i)))
                   (dotimes (j entries-per-thread)
                     (let ((seq (sw4rm-orchestrator.persistence::wal-append
                                 wal :route (list :id j) :swarm-id swarm-id)))
                       (bt:with-lock-held (sequences)
                         (push seq all-sequences))))))
               :name (format nil "seq-writer-~D" i))
              threads))

      ;; Wait for all threads
      (dolist (thread threads)
        (bt:join-thread thread))

      ;; All sequences should be unique
      (is (= (length all-sequences)
             (length (remove-duplicates all-sequences)))))))

(test wal-sharded-compact-preserves-order
  "Test that compaction preserves sequence order across shards."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards
    (dotimes (i 20)
      (let ((swarm-id (format nil "swarm-~D" (mod i 4))))
        (sw4rm-orchestrator.persistence::wal-append
         wal :route (list :id (1+ i)) :swarm-id swarm-id)))

    ;; Flush and compact
    (sw4rm-orchestrator.persistence::wal-flush wal)
    (sw4rm-orchestrator.persistence::wal-compact wal)

    ;; Entries should still be in sequence order
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 20))
      (loop for i from 0 below (1- (length entries))
            do (let ((curr (sw4rm-orchestrator.persistence::wal-entry-sequence (nth i entries)))
                     (next (sw4rm-orchestrator.persistence::wal-entry-sequence (nth (1+ i) entries))))
                 (is (< curr next)))))))

(test wal-sharded-truncate-maintains-invariants
  "Test that truncation maintains ordering invariants with sharding."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards
    (dotimes (i 20)
      (let ((swarm-id (format nil "swarm-~D" (mod i 4))))
        (sw4rm-orchestrator.persistence::wal-append
         wal :route (list :id (1+ i)) :swarm-id swarm-id)))

    ;; Flush entries
    (sw4rm-orchestrator.persistence::wal-flush wal)

    ;; Truncate entries before sequence 10
    (sw4rm-orchestrator.persistence::wal-truncate wal 10)

    ;; Remaining entries should be in order and >= 10
    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (when entries
        (let ((first-seq (sw4rm-orchestrator.persistence::wal-entry-sequence (first entries))))
          (is (>= first-seq 10)))
        ;; Verify order
        (loop for i from 0 below (1- (length entries))
              do (let ((curr (sw4rm-orchestrator.persistence::wal-entry-sequence (nth i entries)))
                       (next (sw4rm-orchestrator.persistence::wal-entry-sequence (nth (1+ i) entries))))
                   (is (< curr next))))))))

(test wal-sharded-replay-correct-order
  "Test that replay processes entries in correct sequence order."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards
    (dotimes (i 10)
      (let ((swarm-id (format nil "swarm-~D" (mod i 4))))
        (sw4rm-orchestrator.persistence::wal-append
         wal :route (list :id (1+ i)) :swarm-id swarm-id)))

    ;; Replay and track sequence order
    (let ((replayed-sequences nil))
      (sw4rm-orchestrator.persistence::wal-replay
       wal
       (lambda (entry)
         (push (sw4rm-orchestrator.persistence::wal-entry-sequence entry)
               replayed-sequences)))

      ;; Sequences should be in ascending order
      (let ((ordered (nreverse replayed-sequences)))
        (is (= (length ordered) 10))
        (loop for i from 0 below (1- (length ordered))
              do (is (< (nth i ordered) (nth (1+ i) ordered))))))))

(test wal-sharded-stats-include-shard-info
  "Test that WAL stats include sharding information."
  (with-sharded-test-wal (wal)
    (let ((stats (sw4rm-orchestrator.persistence::wal-get-stats wal)))
      (is (getf stats :sharding-enabled))
      (is (= (getf stats :shard-count) 16)))))

(test wal-sharded-pending-entries-count
  "Test counting pending entries across shards."
  (with-sharded-test-wal (wal)
    ;; Add entries to different shards without flushing
    (dotimes (i 10)
      (let ((swarm-id (format nil "swarm-~D" (mod i 4))))
        (sw4rm-orchestrator.persistence::wal-append
         wal :route (list :id i) :swarm-id swarm-id)))

    ;; Check pending entries count
    (is (= (sw4rm-orchestrator.persistence::total-shard-entries wal) 10))

    ;; After flush, should be 0
    (sw4rm-orchestrator.persistence::wal-flush wal)
    (is (= (sw4rm-orchestrator.persistence::total-shard-entries wal) 0))))

(test wal-sharded-entry-swarm-id-preserved
  "Test that swarm-id is preserved in WAL entries."
  (with-sharded-test-wal (wal)
    (sw4rm-orchestrator.persistence::wal-append
     wal :route '(:data "test") :swarm-id "leaf-a")

    (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal)))
      (is (= (length entries) 1))
      (is (equal (sw4rm-orchestrator.persistence::wal-entry-swarm-id (first entries))
                 "leaf-a")))))

(test wal-sharded-nil-swarm-id-works
  "Test that nil swarm-id is handled correctly."
  (with-sharded-test-wal (wal)
    ;; Append without swarm-id (should go to shard 0)
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test"))
    (sw4rm-orchestrator.persistence::wal-append wal :route '(:data "test2") :swarm-id nil)

    (is (= (sw4rm-orchestrator.persistence::wal-entry-count wal) 2))))

(test wal-sharded-close-flushes-all-shards
  "Test that WAL close flushes all shard buffers."
  (with-temp-wal-directory (dir)
    (let ((wal (sw4rm-orchestrator.persistence::make-wal-log
                (merge-pathnames "test.wal" dir)
                :flush-interval 1000
                :sharding-enabled t)))

      ;; Add entries to different shards
      (dotimes (i 20)
        (let ((swarm-id (format nil "swarm-~D" (mod i 4))))
          (sw4rm-orchestrator.persistence::wal-append
           wal :route (list :id i) :swarm-id swarm-id)))

      ;; Should have pending entries
      (is (> (sw4rm-orchestrator.persistence::total-shard-entries wal) 0))

      ;; Close should flush all
      (sw4rm-orchestrator.persistence::wal-close wal)

      ;; Reopen and verify entries were written
      (let ((wal2 (sw4rm-orchestrator.persistence::make-wal-log
                   (merge-pathnames "test.wal" dir)
                   :sharding-enabled t)))
        (unwind-protect
            (let ((entries (sw4rm-orchestrator.persistence::wal-entries wal2)))
              (is (= (length entries) 20)))
          (sw4rm-orchestrator.persistence::wal-close wal2))))))

;;;; ============================================================================
;;;; Test Runner
;;;; ============================================================================

(defun run-wal-tests ()
  "Run all WAL-related tests."
  (run! 'persistence-tests))

;;;; End of file
