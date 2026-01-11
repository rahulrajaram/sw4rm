;;;; test/package.lisp
;;;;
;;;; Test package definition for SW4RM orchestrator test suite
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :cl-user)

(defpackage :sw4rm-orchestrator.test
  (:documentation "Test suite for SW4RM orchestrator using FiveAM.")
  (:use :cl :fiveam :sw4rm-orchestrator)
  (:export
   ;; Test suite names
   #:sw4rm-orchestrator-tests
   #:tree-tests
   #:routing-tests
   #:envelope-tests
   #:coordination-tests
   #:persistence-tests
   #:wal-tests
   #:lifecycle-tests
   #:fuzz-tests
   #:integration-tests

   ;; Test runners
   #:run-orchestrator-tests
   #:run-tree-tests
   #:run-routing-tests
   #:run-envelope-tests
   #:run-coordination-tests
   #:run-persistence-tests
   #:run-wal-tests
   #:run-lifecycle-tests
   #:run-fuzz-tests
   #:run-integration-tests))

(in-package :sw4rm-orchestrator.test)

;;;; ============================================================================
;;;; Test suite hierarchy
;;;; ============================================================================

(defun configure-test-logging ()
  "Configure log4cl to write WARN logs to a test log file, suppressing console output.

   Test results will still be printed to console, but log messages are redirected."
  (let* ((tmp-dir (uiop:temporary-directory))
         (log-file (merge-pathnames "sw4rm-orchestrator-test.log" tmp-dir)))
    ;; Don't suppress test output - let FiveAM print test results
    ;; We only want to suppress log4cl messages
    #+log4cl
    (progn
      ;; Set log level to WARN to reduce noise during tests
      (set-config "logging.level" "WARN")
      (set-config "logging.console" nil)
      (set-config "logging.file" (namestring log-file))
      (sw4rm-orchestrator::initialize-logging)
      ;; Additionally configure log4cl directly to ensure console is disabled
      (log4cl::clear-logging-configuration)
      (log:config :warn :daily (namestring log-file) :immediate-flush))))

(configure-test-logging)

(def-suite sw4rm-orchestrator-tests
  :description "Top-level test suite for SW4RM orchestrator")

(def-suite tree-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for SwarmTree ADT (types, leaf, node, traversal)")

(def-suite routing-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for routing algorithms and table management")

(def-suite envelope-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for cross-swarm envelope handling")

(def-suite coordination-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for cross-swarm coordination primitives")

(def-suite persistence-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for checkpointing and WAL")

(def-suite wal-tests
  :in persistence-tests
  :description "Tests for Write-Ahead Log (WAL) durability")

(def-suite lifecycle-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for CLI parsing, startup, shutdown, and degraded mode")

(def-suite fuzz-tests
  :in sw4rm-orchestrator-tests
  :description "Property-based fuzz tests for distributed barrier and routing")

(def-suite integration-tests
  :in sw4rm-orchestrator-tests
  :description "Integration tests with Python sw4rm instances")

;;;; ============================================================================
;;;; Test runners
;;;; ============================================================================

(defun run-orchestrator-tests (&key (verbose t))
  "Run all orchestrator tests.

   Args:
     verbose: Print detailed test output

   Returns:
     T if all tests pass, NIL otherwise."
  (run! 'sw4rm-orchestrator-tests))

(defun run-tree-tests ()
  "Run tree-related tests only."
  (run! 'tree-tests))

(defun run-routing-tests ()
  "Run routing-related tests only."
  (run! 'routing-tests))

(defun run-envelope-tests ()
  "Run envelope-related tests only."
  (run! 'envelope-tests))

(defun run-coordination-tests ()
  "Run coordination-related tests only."
  (run! 'coordination-tests))

(defun run-persistence-tests ()
  "Run persistence-related tests only."
  (run! 'persistence-tests))

(defun run-wal-tests ()
  "Run WAL-specific tests only."
  (run! 'wal-tests))

(defun run-lifecycle-tests ()
  "Run lifecycle tests only (CLI, startup, shutdown, degraded mode)."
  (run! 'lifecycle-tests))

(defun run-fuzz-tests ()
  "Run fuzz tests for distributed barrier and routing strategies.

   These tests use randomized inputs to discover edge cases."
  (run! 'fuzz-tests))

(defun run-integration-tests ()
  "Run integration tests only.

   Note: Integration tests require Python sw4rm instances running."
  (run! 'integration-tests))

;;;; End of file
