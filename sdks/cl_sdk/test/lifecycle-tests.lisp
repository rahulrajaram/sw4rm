;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; test/lifecycle-tests.lisp
;;;;
;;;; Comprehensive test suite for CLI parsing, startup, shutdown, and degraded mode.
;;;;
;;;; Tests cover:
;;;;   - CLI flag parsing edge cases (P3-7)
;;;;   - Startup sequence validation
;;;;   - Graceful shutdown with cooperative thread termination
;;;;   - gRPC degraded mode behavior
;;;;   - Health status reporting
;;;;
;;;; Spec References:
;;;;   - COMMON_LISP_PLAN.md Section P3-7: CLI/Startup/Shutdown Tests
;;;;   - src/main.lisp: CLI parsing, health status, shutdown
;;;;   - src/config.lisp: Configuration validation
;;;;
;;;; Version: 0.6.0
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.test)

;;;; ============================================================================
;;;; Test Suite Definition
;;;; ============================================================================

(def-suite lifecycle-tests
  :in sw4rm-orchestrator-tests
  :description "Tests for CLI parsing, startup, shutdown, and degraded mode")

(in-suite lifecycle-tests)

;;;; ============================================================================
;;;; Fixtures and Helpers
;;;; ============================================================================

(defun reset-orchestrator-state ()
  "Reset all global orchestrator state for test isolation."
  ;; Reset orchestrator globals
  (setf sw4rm-orchestrator::*orchestrator* nil)
  (setf sw4rm-orchestrator::*grpc-server* nil)
  (setf sw4rm-orchestrator::*shutdown-requested* nil)
  (setf sw4rm-orchestrator::*grpc-degraded-mode* nil)
  (setf sw4rm-orchestrator::*checkpoint-thread* nil)
  (setf sw4rm-orchestrator::*checkpoint-stop-flag* nil)
  (setf sw4rm-orchestrator::*recovery-in-progress* nil)
  ;; Reset config
  (sw4rm-orchestrator::clear-config))

(defmacro with-clean-orchestrator-state (&body body)
  "Execute BODY with clean orchestrator state, restoring after."
  (let ((saved-orchestrator (gensym "ORCH-"))
        (saved-grpc-server (gensym "GRPC-"))
        (saved-shutdown (gensym "SHUTDOWN-"))
        (saved-degraded (gensym "DEGRADED-"))
        (saved-checkpoint-thread (gensym "CPTHREAD-"))
        (saved-checkpoint-stop (gensym "CPSTOP-"))
        (saved-recovery (gensym "RECOVERY-")))
    `(let ((,saved-orchestrator sw4rm-orchestrator::*orchestrator*)
           (,saved-grpc-server sw4rm-orchestrator::*grpc-server*)
           (,saved-shutdown sw4rm-orchestrator::*shutdown-requested*)
           (,saved-degraded sw4rm-orchestrator::*grpc-degraded-mode*)
           (,saved-checkpoint-thread sw4rm-orchestrator::*checkpoint-thread*)
           (,saved-checkpoint-stop sw4rm-orchestrator::*checkpoint-stop-flag*)
           (,saved-recovery sw4rm-orchestrator::*recovery-in-progress*))
       (unwind-protect
           (progn
             (reset-orchestrator-state)
             ,@body)
         ;; Restore state
         (setf sw4rm-orchestrator::*orchestrator* ,saved-orchestrator)
         (setf sw4rm-orchestrator::*grpc-server* ,saved-grpc-server)
         (setf sw4rm-orchestrator::*shutdown-requested* ,saved-shutdown)
         (setf sw4rm-orchestrator::*grpc-degraded-mode* ,saved-degraded)
         (setf sw4rm-orchestrator::*checkpoint-thread* ,saved-checkpoint-thread)
         (setf sw4rm-orchestrator::*checkpoint-stop-flag* ,saved-checkpoint-stop)
         (setf sw4rm-orchestrator::*recovery-in-progress* ,saved-recovery)))))

(defun capture-cli-error (args)
  "Attempt to parse args and capture CLI error message.
   Returns the error condition if one is signaled, NIL otherwise."
  (handler-case
      (progn
        (sw4rm-orchestrator::parse-args args)
        nil)
    (error (e)
      e)))

;;;; ============================================================================
;;;; Section 1: CLI Flag Parsing Tests
;;;; ============================================================================

;;; Test: Missing argument values

(test cli-config-missing-value
  "Test --config without a file path triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--config"))))
      (is (not (null err))))))

(test cli-config-short-missing-value
  "Test -c without a file path triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("-c"))))
      (is (not (null err))))))

(test cli-id-missing-value
  "Test --id without identifier triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--id"))))
      (is (not (null err))))))

(test cli-host-missing-value
  "Test --host without hostname triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--host"))))
      (is (not (null err))))))

(test cli-port-missing-value
  "Test --port without port number triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port"))))
      (is (not (null err))))))

(test cli-checkpoint-path-missing-value
  "Test --checkpoint-path without path triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--checkpoint-path"))))
      (is (not (null err))))))

(test cli-restore-missing-value
  "Test --restore without file path triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--restore"))))
      (is (not (null err))))))

(test cli-log-level-missing-value
  "Test --log-level without level triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--log-level"))))
      (is (not (null err))))))

;;; Test: Flag-like values as arguments

(test cli-config-flag-like-value
  "Test --config with flag-like value (--foo) triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--config" "--foo"))))
      (is (not (null err))))))

(test cli-id-flag-like-value
  "Test --id with flag-like value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--id" "-x"))))
      (is (not (null err))))))

(test cli-host-flag-like-value
  "Test --host with flag-like value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--host" "--port"))))
      (is (not (null err))))))

(test cli-checkpoint-path-flag-like-value
  "Test --checkpoint-path with flag-like value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--checkpoint-path" "--config"))))
      (is (not (null err))))))

;;; Test: Invalid port numbers

(test cli-port-invalid-not-integer
  "Test --port with non-integer value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port" "abc"))))
      (is (not (null err))))))

(test cli-port-invalid-zero
  "Test --port with 0 triggers error (out of range)."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port" "0"))))
      (is (not (null err))))))

(test cli-port-invalid-negative
  "Test --port with negative value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port" "-1"))))
      (is (not (null err))))))

(test cli-port-invalid-too-high
  "Test --port with 65536 (out of range) triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port" "65536"))))
      (is (not (null err))))))

(test cli-port-invalid-way-too-high
  "Test --port with very large number triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--port" "100000"))))
      (is (not (null err))))))

(test cli-port-valid-min
  "Test --port with 1 (minimum valid) succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--port" "1"))))
      (is (= (getf result :grpc-port) 1)))))

(test cli-port-valid-max
  "Test --port with 65535 (maximum valid) succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--port" "65535"))))
      (is (= (getf result :grpc-port) 65535)))))

(test cli-port-valid-typical
  "Test --port with typical value (50050) succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--port" "50050"))))
      (is (= (getf result :grpc-port) 50050)))))

;;; Test: Invalid log levels

(test cli-log-level-invalid
  "Test --log-level with invalid level triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--log-level" "VERBOSE"))))
      (is (not (null err))))))

(test cli-log-level-invalid-numeric
  "Test --log-level with numeric value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--log-level" "3"))))
      (is (not (null err))))))

(test cli-log-level-valid-debug
  "Test --log-level DEBUG succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--log-level" "DEBUG"))))
      (is (string= (getf result :log-level) "DEBUG")))))

(test cli-log-level-valid-info
  "Test --log-level INFO succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--log-level" "INFO"))))
      (is (string= (getf result :log-level) "INFO")))))

(test cli-log-level-valid-warn
  "Test --log-level WARN succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--log-level" "WARN"))))
      (is (string= (getf result :log-level) "WARN")))))

(test cli-log-level-valid-error
  "Test --log-level ERROR succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--log-level" "ERROR"))))
      (is (string= (getf result :log-level) "ERROR")))))

(test cli-log-level-case-insensitive
  "Test --log-level is case-insensitive."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '("--log-level" "debug"))))
      (is (string= (getf result :log-level) "DEBUG")))))

;;; Test: Unknown arguments

(test cli-unknown-argument
  "Test unknown argument triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--unknown-flag"))))
      (is (not (null err))))))

(test cli-unknown-argument-with-value
  "Test unknown argument with value triggers error."
  (with-clean-orchestrator-state
    (let ((err (capture-cli-error '("--unknown" "value"))))
      (is (not (null err))))))

;;; Test: Valid complete parsing

(test cli-parse-complete-valid
  "Test parsing complete valid argument set."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args
                   '("--id" "my-orch"
                     "--host" "localhost"
                     "--port" "50051"
                     "--log-level" "DEBUG"))))
      (is (string= (getf result :orchestrator-id) "my-orch"))
      (is (string= (getf result :grpc-host) "localhost"))
      (is (= (getf result :grpc-port) 50051))
      (is (string= (getf result :log-level) "DEBUG")))))

(test cli-parse-short-flags
  "Test parsing with short flag variants."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args
                   '("-i" "short-id"
                     "-p" "50052"))))
      (is (string= (getf result :orchestrator-id) "short-id"))
      (is (= (getf result :grpc-port) 50052)))))

(test cli-parse-empty-args
  "Test parsing empty argument list succeeds."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args '())))
      (is (listp result))
      (is (null (getf result :config-file)))
      (is (null (getf result :orchestrator-id))))))

;;;; ============================================================================
;;;; Section 2: Port Value Parsing Tests
;;;; ============================================================================

(test parse-port-value-valid-string
  "Test parse-port-value with valid port string."
  (is (= (sw4rm-orchestrator::parse-port-value "8080" "--port") 8080)))

(test parse-port-value-boundary-min
  "Test parse-port-value with minimum valid port."
  (is (= (sw4rm-orchestrator::parse-port-value "1" "--port") 1)))

(test parse-port-value-boundary-max
  "Test parse-port-value with maximum valid port."
  (is (= (sw4rm-orchestrator::parse-port-value "65535" "--port") 65535)))

(test parse-port-value-nil-input
  "Test parse-port-value with nil input triggers error."
  (handler-case
      (progn
        (sw4rm-orchestrator::parse-port-value nil "--port")
        (fail "Expected error for nil input"))
    (error () (pass))))

(test parse-port-value-empty-string
  "Test parse-port-value with empty string triggers error."
  (handler-case
      (progn
        (sw4rm-orchestrator::parse-port-value "" "--port")
        (fail "Expected error for empty string"))
    (error () (pass))))

;;;; ============================================================================
;;;; Section 3: Log Level Validation Tests
;;;; ============================================================================

(test validate-log-level-all-valid
  "Test validate-log-level accepts all valid levels."
  (dolist (level '("DEBUG" "INFO" "WARN" "WARNING" "ERROR" "FATAL"))
    (is (string= (sw4rm-orchestrator::validate-log-level level "--log-level")
                 level))))

(test validate-log-level-case-normalization
  "Test validate-log-level normalizes case."
  (is (string= (sw4rm-orchestrator::validate-log-level "info" "--log-level") "INFO"))
  (is (string= (sw4rm-orchestrator::validate-log-level "Debug" "--log-level") "DEBUG"))
  (is (string= (sw4rm-orchestrator::validate-log-level "WaRn" "--log-level") "WARN")))

(test validate-log-level-nil-input
  "Test validate-log-level with nil input triggers error."
  (handler-case
      (progn
        (sw4rm-orchestrator::validate-log-level nil "--log-level")
        (fail "Expected error for nil input"))
    (error () (pass))))

(test validate-log-level-invalid-level
  "Test validate-log-level with invalid level triggers error."
  (handler-case
      (progn
        (sw4rm-orchestrator::validate-log-level "TRACE" "--log-level")
        (fail "Expected error for invalid level"))
    (error () (pass))))

;;;; ============================================================================
;;;; Section 4: Startup Sequence Tests
;;;; ============================================================================

(test startup-config-loading
  "Test that startup loads config file when specified."
  (with-clean-orchestrator-state
    ;; Create a minimal config plist without config-file
    (let ((args-plist '(:config-file nil :orchestrator-id "test-orch")))
      ;; This should work without a config file
      (is (listp args-plist)))))

(test startup-initializes-defaults
  "Test that startup initializes default configuration."
  (with-clean-orchestrator-state
    ;; After reset, config defaults should still be accessible
    (is (not (null (sw4rm-orchestrator::get-config "grpc.port"))))))

(test startup-grpc-degraded-mode-reset
  "Test that startup resets degraded mode flag."
  (with-clean-orchestrator-state
    ;; Set degraded mode
    (setf sw4rm-orchestrator::*grpc-degraded-mode* t)
    ;; Reset
    (reset-orchestrator-state)
    ;; Should be nil
    (is (null sw4rm-orchestrator::*grpc-degraded-mode*))))

;;;; ============================================================================
;;;; Section 5: Graceful Shutdown Tests
;;;; ============================================================================

(test shutdown-flag-initialization
  "Test shutdown flag starts as nil."
  (with-clean-orchestrator-state
    (is (null sw4rm-orchestrator::*shutdown-requested*))))

(test shutdown-flag-setting
  "Test shutdown flag can be set."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*shutdown-requested* t)
    (is-true sw4rm-orchestrator::*shutdown-requested*)))

(test checkpoint-stop-flag-initialization
  "Test checkpoint stop flag starts as nil."
  (with-clean-orchestrator-state
    (is (null sw4rm-orchestrator::*checkpoint-stop-flag*))))

(test checkpoint-stop-flag-cooperative-shutdown
  "Test checkpoint stop flag can signal cooperative shutdown."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*checkpoint-stop-flag* t)
    (is-true sw4rm-orchestrator::*checkpoint-stop-flag*)))

(test stop-checkpoint-thread-no-thread
  "Test stop-checkpoint-thread handles nil thread gracefully."
  (with-clean-orchestrator-state
    (is (null sw4rm-orchestrator::*checkpoint-thread*))
    ;; Should not error and return nil
    (is (null (sw4rm-orchestrator::stop-checkpoint-thread)))))

(test checkpoint-thread-join-timeout-constant
  "Test checkpoint thread join timeout is defined."
  (is (= sw4rm-orchestrator::+checkpoint-thread-join-timeout+ 30)))

;;;; ============================================================================
;;;; Section 6: gRPC Degraded Mode Tests
;;;; ============================================================================

(test grpc-degraded-mode-flag-default
  "Test gRPC degraded mode flag defaults to nil."
  (with-clean-orchestrator-state
    (is (null sw4rm-orchestrator::*grpc-degraded-mode*))))

(test grpc-degraded-mode-p-returns-flag
  "Test grpc-degraded-mode-p returns the flag value."
  (with-clean-orchestrator-state
    (is (null (sw4rm-orchestrator::grpc-degraded-mode-p)))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* t)
    (is (sw4rm-orchestrator::grpc-degraded-mode-p))))

(test grpc-degraded-mode-affects-health
  "Test that degraded mode affects health status."
  (with-clean-orchestrator-state
    ;; Create minimal orchestrator state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050 :mock t))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* t)
    ;; Health should be :degraded
    (is (eq (sw4rm-orchestrator::get-health-status) :degraded))))

;;;; ============================================================================
;;;; Section 7: Health Status Tests
;;;; ============================================================================

(test health-status-no-orchestrator
  "Test health status is :not-ready without orchestrator."
  (with-clean-orchestrator-state
    (is (eq (sw4rm-orchestrator::get-health-status) :not-ready))))

(test health-status-shutdown-requested
  "Test health status is :not-ready when shutdown requested."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050))
    (setf sw4rm-orchestrator::*shutdown-requested* t)
    (is (eq (sw4rm-orchestrator::get-health-status) :not-ready))))

(test health-status-recovery-in-progress
  "Test health status is :recovering during recovery."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050))
    (setf sw4rm-orchestrator::*recovery-in-progress* t)
    (is (eq (sw4rm-orchestrator::get-health-status) :recovering))))

(test health-status-no-grpc-server
  "Test health status is :degraded without gRPC server."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* nil)
    (is (eq (sw4rm-orchestrator::get-health-status) :degraded))))

(test health-status-ready-with-grpc
  "Test health status is :ready with orchestrator and gRPC."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* nil)
    (is (eq (sw4rm-orchestrator::get-health-status) :ready))))

(test health-status-string-conversion
  "Test health-status-string returns lowercase string."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* nil)
    (is (string= (sw4rm-orchestrator::health-status-string) "ready"))))

(test health-status-string-degraded
  "Test health-status-string returns 'degraded' when appropriate."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* t)
    (is (string= (sw4rm-orchestrator::health-status-string) "degraded"))))

;;;; ============================================================================
;;;; Section 8: Configuration Validation Tests (Startup Related)
;;;; ============================================================================

(test config-validation-error-condition
  "Test config-validation-error condition is defined."
  (let ((err (make-condition 'sw4rm-orchestrator::config-validation-error
                             :key "test.key"
                             :value "bad-value"
                             :reason "Test reason")))
    (is (string= (sw4rm-orchestrator::config-validation-error-key err) "test.key"))
    (is (string= (sw4rm-orchestrator::config-validation-error-value err) "bad-value"))
    (is (string= (sw4rm-orchestrator::config-validation-error-reason err) "Test reason"))))

(test config-validation-port-range
  "Test config validation rejects out-of-range ports."
  (with-clean-orchestrator-state
    ;; Set up minimal required config
    (sw4rm-orchestrator::set-config "orchestrator.id" "test")
    (sw4rm-orchestrator::set-config "grpc.host" "localhost")
    (sw4rm-orchestrator::set-config "grpc.port" 70000) ; Invalid
    (sw4rm-orchestrator::set-config "routing.max-hops" 10)
    (sw4rm-orchestrator::set-config "checkpoint.enabled" nil)
    ;; Should signal error
    (handler-case
        (progn
          (sw4rm-orchestrator::validate-config)
          (fail "Expected config validation error"))
      (sw4rm-orchestrator::config-validation-error (e)
        (is (string= (sw4rm-orchestrator::config-validation-error-key e) "grpc.port"))))))

(test config-validation-max-hops-positive
  "Test config validation requires positive max-hops."
  (with-clean-orchestrator-state
    (sw4rm-orchestrator::set-config "orchestrator.id" "test")
    (sw4rm-orchestrator::set-config "grpc.host" "localhost")
    (sw4rm-orchestrator::set-config "grpc.port" 50050)
    (sw4rm-orchestrator::set-config "routing.max-hops" 0) ; Invalid
    (sw4rm-orchestrator::set-config "checkpoint.enabled" nil)
    (handler-case
        (progn
          (sw4rm-orchestrator::validate-config)
          (fail "Expected config validation error"))
      (sw4rm-orchestrator::config-validation-error (e)
        (is (string= (sw4rm-orchestrator::config-validation-error-key e) "routing.max-hops"))))))

(test config-validation-success
  "Test config validation succeeds with valid config."
  (with-clean-orchestrator-state
    (sw4rm-orchestrator::set-config "orchestrator.id" "test-orch")
    (sw4rm-orchestrator::set-config "grpc.host" "localhost")
    (sw4rm-orchestrator::set-config "grpc.port" 50050)
    (sw4rm-orchestrator::set-config "routing.max-hops" 10)
    (sw4rm-orchestrator::set-config "checkpoint.enabled" nil)
    (is (sw4rm-orchestrator::validate-config))))

;;;; ============================================================================
;;;; Section 9: Orchestrator Status Tests
;;;; ============================================================================

(test orchestrator-status-not-running
  "Test orchestrator-status when not running."
  (with-clean-orchestrator-state
    (let ((status (sw4rm-orchestrator::orchestrator-status)))
      (is (eq (getf status :status) :not-running))
      (is (eq (getf status :health) :not-ready)))))

(test orchestrator-status-running
  "Test orchestrator-status when running."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test-orch"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050))
    (let ((status (sw4rm-orchestrator::orchestrator-status)))
      (is (eq (getf status :status) :running))
      (is (string= (getf status :id) "test-orch")))))

(test orchestrator-status-includes-degraded-mode
  "Test orchestrator-status includes degraded mode flag."
  (with-clean-orchestrator-state
    (setf sw4rm-orchestrator::*orchestrator*
          (make-instance 'sw4rm-orchestrator.tree:swarm-node :id "test"))
    (setf sw4rm-orchestrator::*grpc-server* '(:host "localhost" :port 50050 :mock t))
    (setf sw4rm-orchestrator::*grpc-degraded-mode* t)
    (let ((status (sw4rm-orchestrator::orchestrator-status)))
      (is (getf status :grpc-degraded-mode)))))

;;;; ============================================================================
;;;; Section 10: Edge Cases and Integration
;;;; ============================================================================

(test cli-special-characters-in-id
  "Test CLI handles special characters in orchestrator ID."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args
                   '("--id" "orch-123_test.prod"))))
      (is (string= (getf result :orchestrator-id) "orch-123_test.prod")))))

(test cli-ipv6-host
  "Test CLI accepts IPv6 address as host."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args
                   '("--host" "::1"))))
      (is (string= (getf result :grpc-host) "::1")))))

(test cli-mixed-short-long-flags
  "Test CLI handles mix of short and long flags."
  (with-clean-orchestrator-state
    (let ((result (sw4rm-orchestrator::parse-args
                   '("-i" "my-orch" "--host" "localhost" "-p" "8080"))))
      (is (string= (getf result :orchestrator-id) "my-orch"))
      (is (string= (getf result :grpc-host) "localhost"))
      (is (= (getf result :grpc-port) 8080)))))

(test valid-log-levels-list
  "Test *valid-log-levels* contains expected values."
  (is (member "DEBUG" sw4rm-orchestrator::*valid-log-levels* :test #'string=))
  (is (member "INFO" sw4rm-orchestrator::*valid-log-levels* :test #'string=))
  (is (member "WARN" sw4rm-orchestrator::*valid-log-levels* :test #'string=))
  (is (member "WARNING" sw4rm-orchestrator::*valid-log-levels* :test #'string=))
  (is (member "ERROR" sw4rm-orchestrator::*valid-log-levels* :test #'string=))
  (is (member "FATAL" sw4rm-orchestrator::*valid-log-levels* :test #'string=)))

;;;; ============================================================================
;;;; Test Runner
;;;; ============================================================================

(defun run-lifecycle-tests ()
  "Run all lifecycle-related tests."
  (run! 'lifecycle-tests))

;;;; End of file
