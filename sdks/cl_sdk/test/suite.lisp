;;;; suite.lisp - FiveAM test suite for the SW4RM Common Lisp SDK
;;;;
;;;; Covers: constants parity, ack-manager lifecycle, control types,
;;;;         activity-buffer operations, and client stub error signaling.
;;;;
;;;; Run with:
;;;;   (ql:quickload :fiveam)
;;;;   (load "test/suite.lisp")
;;;;   (fiveam:run! 'sw4rm-test::sw4rm-suite)

;;; -----------------------------------------------------------------------
;;; Package
;;; -----------------------------------------------------------------------

(defpackage :sw4rm-test
  (:use :cl :fiveam :sw4rm))

(in-package :sw4rm-test)

(def-suite sw4rm-suite :description "SW4RM CL SDK tests")
(in-suite sw4rm-suite)


;;; =======================================================================
;;;  1. Constants Parity
;;; =======================================================================
;;;
;;; Verify that the Lisp constants match the canonical protobuf enum values.
;;; Any drift here means the SDK is out of sync with the wire protocol.

(def-suite constants-suite :description "Protocol constant parity checks"
  :in sw4rm-suite)
(in-suite constants-suite)

;; -- MessageType enum (spec S11) ------------------------------------------

(test message-type-unspecified-is-0
  "MessageType UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+message-type-unspecified+)))

(test message-type-control-is-1
  "MessageType CONTROL must be 1."
  (is (= 1 sw4rm::+control+)))

(test message-type-data-is-2
  "MessageType DATA must be 2."
  (is (= 2 sw4rm::+data+)))

(test message-type-heartbeat-is-3
  "MessageType HEARTBEAT must be 3."
  (is (= 3 sw4rm::+heartbeat+)))

(test message-type-notification-is-4
  "MessageType NOTIFICATION must be 4."
  (is (= 4 sw4rm::+notification+)))

(test message-type-acknowledgement-is-5
  "MessageType ACKNOWLEDGEMENT must be 5."
  (is (= 5 sw4rm::+acknowledgement+)))

(test message-type-hitl-invocation-is-6
  "MessageType HITL_INVOCATION must be 6."
  (is (= 6 sw4rm::+hitl-invocation+)))

(test message-type-worktree-control-is-7
  "MessageType WORKTREE_CONTROL must be 7."
  (is (= 7 sw4rm::+worktree-control+)))

(test message-type-negotiation-is-8
  "MessageType NEGOTIATION must be 8."
  (is (= 8 sw4rm::+negotiation+)))

(test message-type-tool-call-is-9
  "MessageType TOOL_CALL must be 9."
  (is (= 9 sw4rm::+tool-call+)))

(test message-type-tool-result-is-10
  "MessageType TOOL_RESULT must be 10."
  (is (= 10 sw4rm::+tool-result+)))

(test message-type-tool-error-is-11
  "MessageType TOOL_ERROR must be 11."
  (is (= 11 sw4rm::+tool-error+)))

;; -- AckStage enum (spec S11) ---------------------------------------------

(test ack-stage-unspecified-is-0
  "AckStage UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+ack-stage-unspecified+)))

(test ack-stage-received-is-1
  "AckStage RECEIVED must be 1."
  (is (= 1 sw4rm::+received+)))

(test ack-stage-read-is-2
  "AckStage READ must be 2."
  (is (= 2 sw4rm::+read+)))

(test ack-stage-fulfilled-is-3
  "AckStage FULFILLED must be 3."
  (is (= 3 sw4rm::+fulfilled+)))

(test ack-stage-rejected-is-4
  "AckStage REJECTED must be 4."
  (is (= 4 sw4rm::+rejected+)))

(test ack-stage-failed-is-5
  "AckStage FAILED must be 5."
  (is (= 5 sw4rm::+failed+)))

(test ack-stage-timed-out-is-6
  "AckStage TIMED_OUT must be 6."
  (is (= 6 sw4rm::+timed-out+)))

;; -- ErrorCode enum (spec S11) --------------------------------------------

(test error-code-unspecified-is-0
  "ErrorCode UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+error-code-unspecified+)))

(test error-code-buffer-full-is-1
  "ErrorCode BUFFER_FULL must be 1."
  (is (= 1 sw4rm::+buffer-full+)))

(test error-code-no-route-is-2
  "ErrorCode NO_ROUTE must be 2."
  (is (= 2 sw4rm::+no-route+)))

(test error-code-ack-timeout-is-3
  "ErrorCode ACK_TIMEOUT must be 3."
  (is (= 3 sw4rm::+ack-timeout+)))

(test error-code-internal-is-99
  "ErrorCode INTERNAL_ERROR must be 99."
  (is (= 99 sw4rm::+internal-error+)))

(test error-code-validation-is-6
  "ErrorCode VALIDATION_ERROR must be 6."
  (is (= 6 sw4rm::+validation-error+)))

(test error-code-permission-denied-is-7
  "ErrorCode PERMISSION_DENIED must be 7."
  (is (= 7 sw4rm::+permission-denied+)))

(test error-code-ttl-expired-is-13
  "ErrorCode TTL_EXPIRED must be 13."
  (is (= 13 sw4rm::+ttl-expired+)))

(test error-code-duplicate-detected-is-14
  "ErrorCode DUPLICATE_DETECTED must be 14."
  (is (= 14 sw4rm::+duplicate-detected+)))

(test error-code-already-in-progress-is-15
  "ErrorCode ALREADY_IN_PROGRESS must be 15."
  (is (= 15 sw4rm::+already-in-progress+)))

;; -- AgentState enum (spec S8) --------------------------------------------

(test agent-state-unspecified-is-0
  "AgentState UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+agent-state-unspecified+)))

(test agent-state-initializing-is-1
  "AgentState INITIALIZING must be 1."
  (is (= 1 sw4rm::+initializing+)))

(test agent-state-runnable-is-2
  "AgentState RUNNABLE must be 2."
  (is (= 2 sw4rm::+runnable+)))

(test agent-state-scheduled-is-3
  "AgentState SCHEDULED must be 3."
  (is (= 3 sw4rm::+scheduled+)))

(test agent-state-running-is-4
  "AgentState RUNNING must be 4."
  (is (= 4 sw4rm::+running+)))

(test agent-state-waiting-is-5
  "AgentState WAITING must be 5."
  (is (= 5 sw4rm::+waiting+)))

(test agent-state-completed-is-9
  "AgentState COMPLETED must be 9."
  (is (= 9 sw4rm::+completed+)))

(test agent-state-shutting-down-is-11
  "AgentState SHUTTING_DOWN must be 11."
  (is (= 11 sw4rm::+shutting-down+)))

(test agent-state-recovering-is-12
  "AgentState RECOVERING must be 12."
  (is (= 12 sw4rm::+recovering+)))

;; -- WorktreeState enum (spec S16) ----------------------------------------

(test worktree-state-unspecified-is-0
  "WorktreeState UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+worktree-state-unspecified+)))

(test worktree-state-unbound-is-1
  "WorktreeState UNBOUND must be 1."
  (is (= 1 sw4rm::+unbound+)))

(test worktree-state-bound-home-is-2
  "WorktreeState BOUND_HOME must be 2."
  (is (= 2 sw4rm::+bound-home+)))

(test worktree-state-switch-pending-is-3
  "WorktreeState SWITCH_PENDING must be 3."
  (is (= 3 sw4rm::+switch-pending+)))

(test worktree-state-bound-non-home-is-4
  "WorktreeState BOUND_NON_HOME must be 4."
  (is (= 4 sw4rm::+bound-non-home+)))

(test worktree-state-bind-failed-is-5
  "WorktreeState BIND_FAILED must be 5."
  (is (= 5 sw4rm::+bind-failed+)))

;; -- CommunicationClass enum (spec S7.3) ----------------------------------

(test communication-class-unspecified-is-0
  "CommunicationClass UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+communication-class-unspecified+)))

(test communication-class-privileged-is-1
  "CommunicationClass PRIVILEGED must be 1."
  (is (= 1 sw4rm::+privileged+)))

(test communication-class-standard-is-2
  "CommunicationClass STANDARD must be 2."
  (is (= 2 sw4rm::+standard+)))

(test communication-class-bulk-is-3
  "CommunicationClass BULK must be 3."
  (is (= 3 sw4rm::+bulk+)))

;; -- EnvelopeState enum (spec S11) ----------------------------------------

(test envelope-state-unspecified-is-0
  "EnvelopeState UNSPECIFIED must be 0."
  (is (= 0 sw4rm::+envelope-state-unspecified+)))

(test envelope-state-sent-is-1
  "EnvelopeState SENT must be 1."
  (is (= 1 sw4rm::+sent+)))

(test envelope-state-received-is-2
  "EnvelopeState RECEIVED must be 2."
  (is (= 2 sw4rm::+received-envelope+)))

(test envelope-state-fulfilled-is-4
  "EnvelopeState FULFILLED must be 4."
  (is (= 4 sw4rm::+fulfilled-envelope+)))

(test envelope-state-timed-out-is-7
  "EnvelopeState TIMED_OUT must be 7."
  (is (= 7 sw4rm::+timed-out-envelope+)))

;; -- Default ports (spec S5) ----------------------------------------------

(test default-router-port
  "Default router port must be 50051."
  (is (= 50051 sw4rm::+default-router-port+)))

(test default-registry-port
  "Default registry port must be 50052."
  (is (= 50052 sw4rm::+default-registry-port+)))

(test default-scheduler-port
  "Default scheduler port must be 50053."
  (is (= 50053 sw4rm::+default-scheduler-port+)))

(test default-hitl-port
  "Default HITL port must be 50054."
  (is (= 50054 sw4rm::+default-hitl-port+)))

;; -- Default parameters ---------------------------------------------------

(test default-timeout-ms
  "Default timeout must be 30000 ms."
  (is (= 30000 sw4rm::*default-timeout-ms*)))

(test default-ack-timeout-ms
  "Default ACK timeout must be 10000 ms (per spec S11)."
  (is (= 10000 sw4rm::*default-ack-timeout-ms*)))

(test default-heartbeat-interval-ms
  "Default heartbeat interval must be 30000 ms."
  (is (= 30000 sw4rm::*default-heartbeat-interval-ms*)))

(test default-activity-buffer-size
  "Default activity buffer size must be 10000 (per spec S10.1)."
  (is (= 10000 sw4rm::*default-activity-buffer-size*)))

(test default-deduplication-window
  "Default deduplication window must be 3600 seconds (per spec S11.2)."
  (is (= 3600 sw4rm::*default-deduplication-window-seconds*)))


;;; =======================================================================
;;;  2. ACK Manager
;;; =======================================================================

(def-suite ack-manager-suite :description "ACK lifecycle manager tests"
  :in sw4rm-suite)
(in-suite ack-manager-suite)

;; -- Construction ---------------------------------------------------------

(test make-ack-manager-basic
  "Creating an ack-manager with defaults should succeed."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (is (string= "agent-1" (sw4rm::ack-manager-agent-id mgr)))
    (is (= 0 (sw4rm::ack-manager-count mgr)))
    (is (eq t (sw4rm::ack-manager-auto-ack-p mgr)))
    (is (= 10 (sw4rm::ack-manager-ack-timeout-seconds mgr)))))

(test make-ack-manager-custom-timeout
  "Creating an ack-manager with a custom timeout should store the value."
  (let ((mgr (sw4rm::make-ack-manager "agent-2" :ack-timeout-seconds 30)))
    (is (= 30 (sw4rm::ack-manager-ack-timeout-seconds mgr)))))

(test make-ack-manager-auto-ack-disabled
  "Creating an ack-manager with auto-ack-p NIL should store the value."
  (let ((mgr (sw4rm::make-ack-manager "agent-3" :auto-ack-p nil)))
    (is (eq nil (sw4rm::ack-manager-auto-ack-p mgr)))))

(test make-ack-manager-empty-agent-id-signals
  "Creating an ack-manager with an empty agent-id must signal validation-error."
  (signals sw4rm::validation-error
    (sw4rm::make-ack-manager "")))

(test make-ack-manager-invalid-timeout-signals
  "Creating an ack-manager with a non-positive timeout must signal validation-error."
  (signals sw4rm::validation-error
    (sw4rm::make-ack-manager "agent-x" :ack-timeout-seconds 0)))

;; -- track-outgoing -------------------------------------------------------

(test track-outgoing-creates-record
  "track-outgoing must create a record with direction :OUT and stage UNSPECIFIED."
  (let* ((mgr (sw4rm::make-ack-manager "agent-1"))
         (rec (sw4rm::track-outgoing mgr "msg-001")))
    (is (string= "msg-001" (sw4rm::ack-record-message-id rec)))
    (is (= sw4rm::+ack-stage-unspecified+ (sw4rm::ack-record-stage rec)))
    (is (eq :out (sw4rm::ack-record-direction rec)))
    (is (= 1 (sw4rm::ack-manager-count mgr)))))

(test track-outgoing-duplicate-signals
  "track-outgoing must signal validation-error for a duplicate message-id."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (signals sw4rm::validation-error
      (sw4rm::track-outgoing mgr "msg-001"))))

;; -- track-incoming -------------------------------------------------------

(test track-incoming-creates-record
  "track-incoming must create a record with direction :IN and stage RECEIVED."
  (let* ((mgr (sw4rm::make-ack-manager "agent-1"))
         (rec (sw4rm::track-incoming mgr "msg-100")))
    (is (string= "msg-100" (sw4rm::ack-record-message-id rec)))
    (is (= sw4rm::+received+ (sw4rm::ack-record-stage rec)))
    (is (eq :in (sw4rm::ack-record-direction rec)))))

(test track-incoming-duplicate-signals
  "track-incoming must signal validation-error for a duplicate message-id."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-incoming mgr "msg-100")
    (signals sw4rm::validation-error
      (sw4rm::track-incoming mgr "msg-100"))))

;; -- update-ack -----------------------------------------------------------

(test update-ack-changes-stage
  "update-ack must update the stage on a tracked record."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (let ((rec (sw4rm::update-ack mgr "msg-001" sw4rm::+received+)))
      (is (= sw4rm::+received+ (sw4rm::ack-record-stage rec))))))

(test update-ack-with-error-code
  "update-ack must update the error code when supplied."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (sw4rm::update-ack mgr "msg-001" sw4rm::+failed+
                       :error-code sw4rm::+ack-timeout+)
    (let ((rec (sw4rm::ack-manager-get mgr "msg-001")))
      (is (= sw4rm::+failed+ (sw4rm::ack-record-stage rec)))
      (is (= sw4rm::+ack-timeout+ (sw4rm::ack-record-error-code rec))))))

(test update-ack-with-note
  "update-ack must update the note when supplied."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (sw4rm::update-ack mgr "msg-001" sw4rm::+rejected+
                       :note "payload too large")
    (let ((rec (sw4rm::ack-manager-get mgr "msg-001")))
      (is (string= "payload too large" (sw4rm::ack-record-note rec))))))

(test update-ack-unknown-message-signals
  "update-ack for an untracked message must signal sw4rm-error."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (signals sw4rm::sw4rm-error
      (sw4rm::update-ack mgr "nonexistent" sw4rm::+received+))))

;; -- get-unacked ----------------------------------------------------------

(test get-unacked-returns-non-terminal
  "get-unacked must return only records in non-terminal stages."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (sw4rm::track-outgoing mgr "msg-002")
    (sw4rm::track-outgoing mgr "msg-003")
    ;; Advance msg-002 to FULFILLED (terminal)
    (sw4rm::update-ack mgr "msg-002" sw4rm::+fulfilled+)
    (let ((unacked (sw4rm::get-unacked mgr)))
      ;; msg-001 and msg-003 remain non-terminal
      (is (= 2 (length unacked)))
      (is (every (lambda (r)
                   (not (sw4rm::terminal-ack-stage-p
                         (sw4rm::ack-record-stage r))))
                 unacked)))))

(test get-unacked-filters-by-direction
  "get-unacked with :direction must filter correctly."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "out-001")
    (sw4rm::track-incoming mgr "in-001")
    (let ((out-only (sw4rm::get-unacked mgr :direction :out))
          (in-only  (sw4rm::get-unacked mgr :direction :in)))
      (is (= 1 (length out-only)))
      (is (eq :out (sw4rm::ack-record-direction (first out-only))))
      (is (= 1 (length in-only)))
      (is (eq :in (sw4rm::ack-record-direction (first in-only)))))))

(test get-unacked-empty-when-all-terminal
  "get-unacked must return empty list when all messages are terminal."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (sw4rm::update-ack mgr "msg-001" sw4rm::+fulfilled+)
    (is (null (sw4rm::get-unacked mgr)))))

;; -- remove-ack -----------------------------------------------------------

(test remove-ack-returns-record
  "remove-ack must return the removed record."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (sw4rm::track-outgoing mgr "msg-001")
    (let ((removed (sw4rm::remove-ack mgr "msg-001")))
      (is (not (null removed)))
      (is (string= "msg-001" (sw4rm::ack-record-message-id removed)))
      (is (= 0 (sw4rm::ack-manager-count mgr))))))

(test remove-ack-nonexistent-returns-nil
  "remove-ack for an untracked message must return NIL."
  (let ((mgr (sw4rm::make-ack-manager "agent-1")))
    (is (null (sw4rm::remove-ack mgr "nonexistent")))))

;; -- terminal-ack-stage-p -------------------------------------------------

(test terminal-stages-are-terminal
  "FULFILLED, REJECTED, FAILED, and TIMED_OUT must be terminal."
  (is (sw4rm::terminal-ack-stage-p sw4rm::+fulfilled+))
  (is (sw4rm::terminal-ack-stage-p sw4rm::+rejected+))
  (is (sw4rm::terminal-ack-stage-p sw4rm::+failed+))
  (is (sw4rm::terminal-ack-stage-p sw4rm::+timed-out+)))

(test non-terminal-stages-are-not-terminal
  "UNSPECIFIED, RECEIVED, and READ must not be terminal."
  (is (not (sw4rm::terminal-ack-stage-p sw4rm::+ack-stage-unspecified+)))
  (is (not (sw4rm::terminal-ack-stage-p sw4rm::+received+)))
  (is (not (sw4rm::terminal-ack-stage-p sw4rm::+read+))))

;; -- reconcile-stale ------------------------------------------------------

(test reconcile-stale-finds-old-records
  "reconcile-stale must return records older than the timeout threshold."
  (let ((mgr (sw4rm::make-ack-manager "agent-1" :ack-timeout-seconds 1)))
    ;; Track a message and manually backdate its timestamp
    (sw4rm::track-outgoing mgr "msg-old")
    (let ((rec (sw4rm::ack-manager-get mgr "msg-old")))
      ;; Set timestamp to 5 seconds ago (well past 1-second timeout)
      (setf (sw4rm::ack-record-timestamp-ms rec)
            (- (sw4rm::current-time-ms) 5000)))
    (let ((stale (sw4rm::reconcile-stale mgr)))
      (is (= 1 (length stale)))
      (is (string= "msg-old"
                    (sw4rm::ack-record-message-id (first stale)))))))

(test reconcile-stale-ignores-terminal
  "reconcile-stale must not return records in terminal stages even if old."
  (let ((mgr (sw4rm::make-ack-manager "agent-1" :ack-timeout-seconds 1)))
    (sw4rm::track-outgoing mgr "msg-done")
    (sw4rm::update-ack mgr "msg-done" sw4rm::+fulfilled+)
    ;; Backdate the record
    (let ((rec (sw4rm::ack-manager-get mgr "msg-done")))
      (setf (sw4rm::ack-record-timestamp-ms rec)
            (- (sw4rm::current-time-ms) 5000)))
    (is (null (sw4rm::reconcile-stale mgr)))))

(test reconcile-stale-ignores-recent
  "reconcile-stale must not return recently-created records."
  (let ((mgr (sw4rm::make-ack-manager "agent-1" :ack-timeout-seconds 60)))
    (sw4rm::track-outgoing mgr "msg-fresh")
    (is (null (sw4rm::reconcile-stale mgr)))))

;; -- make-ack-record validation -------------------------------------------

(test make-ack-record-requires-message-id
  "make-ack-record must signal validation-error when message-id is empty."
  (signals sw4rm::validation-error
    (sw4rm::make-ack-record :message-id "")))

(test make-ack-record-rejects-invalid-direction
  "make-ack-record must signal validation-error for invalid direction."
  (signals sw4rm::validation-error
    (sw4rm::make-ack-record :message-id "test" :direction :sideways)))

(test make-ack-record-defaults
  "make-ack-record defaults should match spec expectations."
  (let ((rec (sw4rm::make-ack-record :message-id "test-id")))
    (is (= sw4rm::+ack-stage-unspecified+ (sw4rm::ack-record-stage rec)))
    (is (= sw4rm::+error-code-unspecified+ (sw4rm::ack-record-error-code rec)))
    (is (eq :out (sw4rm::ack-record-direction rec)))
    (is (string= "" (sw4rm::ack-record-note rec)))
    (is (> (sw4rm::ack-record-timestamp-ms rec) 0))))


;;; =======================================================================
;;;  3. Control Types
;;; =======================================================================

(def-suite control-suite :description "Control message type tests"
  :in sw4rm-suite)
(in-suite control-suite)

;; -- Content type constants -----------------------------------------------

(test ct-scheduler-command-v1-value
  "Scheduler command content type must match the canonical MIME string."
  (is (string= "application/vnd.sw4rm.scheduler.command+json;v=1"
                sw4rm::+ct-scheduler-command-v1+)))

(test ct-agent-report-v1-value
  "Agent report content type must match the canonical MIME string."
  (is (string= "application/vnd.sw4rm.agent.report+json;v=1"
                sw4rm::+ct-agent-report-v1+)))

;; -- scheduler-stage conversions ------------------------------------------

(test scheduler-stage-to-string-prompt
  "scheduler-stage-to-string for :PROMPT must return \"prompt\"."
  (is (string= "prompt" (sw4rm::scheduler-stage-to-string :prompt))))

(test scheduler-stage-to-string-plan
  "scheduler-stage-to-string for :PLAN must return \"plan\"."
  (is (string= "plan" (sw4rm::scheduler-stage-to-string :plan))))

(test scheduler-stage-to-string-run
  "scheduler-stage-to-string for :RUN must return \"run\"."
  (is (string= "run" (sw4rm::scheduler-stage-to-string :run))))

(test scheduler-stage-to-string-invalid-signals
  "scheduler-stage-to-string for an invalid keyword must signal a type-error."
  (signals type-error
    (sw4rm::scheduler-stage-to-string :invalid)))

(test string-to-scheduler-stage-prompt
  "string-to-scheduler-stage for \"prompt\" must return :PROMPT."
  (is (eq :prompt (sw4rm::string-to-scheduler-stage "prompt"))))

(test string-to-scheduler-stage-case-insensitive
  "string-to-scheduler-stage must be case-insensitive."
  (is (eq :plan (sw4rm::string-to-scheduler-stage "Plan")))
  (is (eq :run  (sw4rm::string-to-scheduler-stage "RUN"))))

(test string-to-scheduler-stage-invalid-signals
  "string-to-scheduler-stage for an invalid string must signal an error."
  (signals type-error
    (sw4rm::string-to-scheduler-stage "execute")))

;; -- SchedulerCommandV1 ---------------------------------------------------

(test make-scheduler-command-v1-basic
  "Creating a SchedulerCommandV1 with stage only."
  (let ((cmd (sw4rm::make-scheduler-command-v1 :prompt)))
    (is (eq :prompt (sw4rm::scheduler-command-v1-stage cmd)))
    (is (null (sw4rm::scheduler-command-v1-input cmd)))))

(test make-scheduler-command-v1-with-input
  "Creating a SchedulerCommandV1 with stage and input."
  (let* ((input '((:task . "analyze") (:depth . 3)))
         (cmd (sw4rm::make-scheduler-command-v1 :run :input input)))
    (is (eq :run (sw4rm::scheduler-command-v1-stage cmd)))
    (is (equal input (sw4rm::scheduler-command-v1-input cmd)))))

(test scheduler-command-v1-to-alist-no-input
  "to-alist for a command without input should contain only :STAGE."
  (let* ((cmd (sw4rm::make-scheduler-command-v1 :plan))
         (alist (sw4rm::scheduler-command-v1-to-alist cmd)))
    (is (string= "plan" (cdr (assoc :stage alist))))
    ;; No :INPUT key when input is NIL
    (is (null (assoc :input alist)))))

(test scheduler-command-v1-to-alist-with-input
  "to-alist for a command with input should contain both :STAGE and :INPUT."
  (let* ((input '((:key . "value")))
         (cmd (sw4rm::make-scheduler-command-v1 :prompt :input input))
         (alist (sw4rm::scheduler-command-v1-to-alist cmd)))
    (is (string= "prompt" (cdr (assoc :stage alist))))
    (is (equal input (cdr (assoc :input alist))))))

(test alist-to-scheduler-command-v1-roundtrip
  "alist-to-scheduler-command-v1 should reconstruct the original command."
  (let* ((original (sw4rm::make-scheduler-command-v1 :run
                     :input '((:x . 1))))
         (alist (sw4rm::scheduler-command-v1-to-alist original))
         (reconstructed (sw4rm::alist-to-scheduler-command-v1 alist)))
    (is (eq :run (sw4rm::scheduler-command-v1-stage reconstructed)))
    (is (equal '((:x . 1))
               (sw4rm::scheduler-command-v1-input reconstructed)))))

;; -- AgentReportFileV1 ----------------------------------------------------

(test make-agent-report-file-v1-basic
  "Creating an AgentReportFileV1 should store path and b64."
  (let ((f (sw4rm::make-agent-report-file-v1 "src/main.py" "aGVsbG8=")))
    (is (string= "src/main.py" (sw4rm::agent-report-file-v1-path f)))
    (is (string= "aGVsbG8=" (sw4rm::agent-report-file-v1-b64 f)))))

(test agent-report-file-v1-alist-roundtrip
  "AgentReportFileV1 should survive alist roundtrip."
  (let* ((original (sw4rm::make-agent-report-file-v1 "docs/readme.md" "ZGJVZQ=="))
         (alist (sw4rm::agent-report-file-v1-to-alist original))
         (rebuilt (sw4rm::alist-to-agent-report-file-v1 alist)))
    (is (string= (sw4rm::agent-report-file-v1-path original)
                  (sw4rm::agent-report-file-v1-path rebuilt)))
    (is (string= (sw4rm::agent-report-file-v1-b64 original)
                  (sw4rm::agent-report-file-v1-b64 rebuilt)))))

;; -- AgentReportV1 --------------------------------------------------------

(test make-agent-report-v1-minimal
  "Creating an AgentReportV1 with no fields should succeed."
  (let ((rpt (sw4rm::make-agent-report-v1)))
    (is (null (sw4rm::agent-report-v1-agent-id rpt)))
    (is (null (sw4rm::agent-report-v1-stage rpt)))
    (is (null (sw4rm::agent-report-v1-success rpt)))
    (is (null (sw4rm::agent-report-v1-files rpt)))
    (is (null (sw4rm::agent-report-v1-logs rpt)))
    (is (null (sw4rm::agent-report-v1-error rpt)))))

(test make-agent-report-v1-full
  "Creating an AgentReportV1 with all fields populated."
  (let* ((file (sw4rm::make-agent-report-file-v1 "out.txt" "Zm9v"))
         (rpt (sw4rm::make-agent-report-v1
                :agent-id "agent-7"
                :stage "generate"
                :success :true
                :files (list file)
                :logs '("line1" "line2")
                :error nil)))
    (is (string= "agent-7" (sw4rm::agent-report-v1-agent-id rpt)))
    (is (string= "generate" (sw4rm::agent-report-v1-stage rpt)))
    (is (eq :true (sw4rm::agent-report-v1-success rpt)))
    (is (= 1 (length (sw4rm::agent-report-v1-files rpt))))
    (is (equal '("line1" "line2") (sw4rm::agent-report-v1-logs rpt)))))

(test agent-report-v1-to-alist-omits-nil-fields
  "to-alist should omit fields that are NIL."
  (let* ((rpt (sw4rm::make-agent-report-v1 :agent-id "a1"))
         (alist (sw4rm::agent-report-v1-to-alist rpt)))
    ;; Only :AGENT-ID should be present
    (is (string= "a1" (cdr (assoc :agent-id alist))))
    (is (null (assoc :stage alist)))
    (is (null (assoc :files alist)))
    (is (null (assoc :logs alist)))
    (is (null (assoc :error alist)))))

(test agent-report-v1-alist-roundtrip
  "AgentReportV1 should survive alist roundtrip."
  (let* ((file (sw4rm::make-agent-report-file-v1 "a.py" "YQ=="))
         (original (sw4rm::make-agent-report-v1
                     :agent-id "agent-x"
                     :stage "test"
                     :success :true
                     :files (list file)
                     :logs '("ok")
                     :error nil))
         (alist (sw4rm::agent-report-v1-to-alist original))
         (rebuilt (sw4rm::alist-to-agent-report-v1 alist)))
    (is (string= "agent-x" (sw4rm::agent-report-v1-agent-id rebuilt)))
    (is (string= "test" (sw4rm::agent-report-v1-stage rebuilt)))
    (is (eq :true (sw4rm::agent-report-v1-success rebuilt)))
    (is (= 1 (length (sw4rm::agent-report-v1-files rebuilt))))
    (is (equal '("ok") (sw4rm::agent-report-v1-logs rebuilt)))))

;; -- Path normalisation ---------------------------------------------------

(test normalize-posix-path-simple
  "Simple path should pass through unchanged."
  (is (string= "src/main.py" (sw4rm::normalize-posix-path "src/main.py"))))

(test normalize-posix-path-backslashes
  "Backslashes should be converted to forward slashes."
  (is (string= "src/main.py" (sw4rm::normalize-posix-path "src\\main.py"))))

(test normalize-posix-path-dot-components
  "Current-directory components should be removed."
  (is (string= "src/main.py" (sw4rm::normalize-posix-path "./src/./main.py"))))

(test normalize-posix-path-dotdot-components
  "Parent-directory components should be resolved."
  (is (string= "main.py" (sw4rm::normalize-posix-path "src/../main.py"))))

(test normalize-posix-path-duplicate-slashes
  "Duplicate slashes should be collapsed."
  (is (string= "src/main.py" (sw4rm::normalize-posix-path "src//main.py"))))

(test normalize-posix-path-complex
  "Complex path with mixed issues."
  (is (string= "b/file.txt"
                (sw4rm::normalize-posix-path "a/../b/./c/../file.txt"))))

(test normalize-posix-path-empty
  "Empty path should produce empty string."
  (is (string= "" (sw4rm::normalize-posix-path ""))))

(test normalize-agent-report-paths-normalizes-files
  "normalize-agent-report-paths must normalize all file paths in a report."
  (let* ((f1 (sw4rm::make-agent-report-file-v1 "src\\..\\out/file.txt" "YQ=="))
         (f2 (sw4rm::make-agent-report-file-v1 "./docs//readme.md" "Yg=="))
         (rpt (sw4rm::make-agent-report-v1 :files (list f1 f2)))
         (normalized (sw4rm::normalize-agent-report-paths rpt))
         (files (sw4rm::agent-report-v1-files normalized)))
    (is (= 2 (length files)))
    (is (string= "out/file.txt"
                  (sw4rm::agent-report-file-v1-path (first files))))
    (is (string= "docs/readme.md"
                  (sw4rm::agent-report-file-v1-path (second files))))))

(test normalize-agent-report-paths-no-files
  "normalize-agent-report-paths on a report with no files returns the same report."
  (let* ((rpt (sw4rm::make-agent-report-v1 :agent-id "a1"))
         (result (sw4rm::normalize-agent-report-paths rpt)))
    ;; When no files, the original report object is returned
    (is (eq rpt result))))

(test normalize-agent-report-paths-preserves-other-fields
  "normalize-agent-report-paths must not alter non-file fields."
  (let* ((f (sw4rm::make-agent-report-file-v1 "a\\b.txt" "YQ=="))
         (rpt (sw4rm::make-agent-report-v1
                :agent-id "agent-z"
                :stage "build"
                :success :false
                :files (list f)
                :logs '("building...")
                :error "oops"))
         (normalized (sw4rm::normalize-agent-report-paths rpt)))
    (is (string= "agent-z" (sw4rm::agent-report-v1-agent-id normalized)))
    (is (string= "build" (sw4rm::agent-report-v1-stage normalized)))
    (is (eq :false (sw4rm::agent-report-v1-success normalized)))
    (is (equal '("building...") (sw4rm::agent-report-v1-logs normalized)))
    (is (string= "oops" (sw4rm::agent-report-v1-error normalized)))))


;;; =======================================================================
;;;  4. Activity Buffer
;;; =======================================================================
;;;
;;; Note: activity-buffer.lisp uses the :SW4RM-SDK package (not :SW4RM).
;;; We reference symbols via the full package prefix. If the package is not
;;; loaded, these tests will be skipped by the condition in the suite runner.

(def-suite activity-buffer-suite
  :description "Activity buffer tests (sw4rm-sdk package)"
  :in sw4rm-suite)
(in-suite activity-buffer-suite)

;; We wrap activity-buffer tests in a feature check since the package may
;; differ from the rest of the SDK.

(test activity-buffer-package-exists
  "The SW4RM-SDK package must exist for activity-buffer tests."
  (is (find-package :sw4rm-sdk)))

;; The remaining activity-buffer tests use fully-qualified symbols so they
;; compile even when sw4rm-sdk is not loaded; they will simply fail at
;; runtime with a clear message if the package is absent.
;;
;; We use FUNCALL + INTERN to decouple from compile-time package presence.

(defun %ab-sym (name)
  "Resolve a symbol in the SW4RM-SDK package, or signal an error."
  (or (find-symbol (string-upcase name) :sw4rm-sdk)
      (error "Symbol ~A not found in SW4RM-SDK" name)))

(defun %make-ab (&rest args)
  "Create an activity-buffer via the SW4RM-SDK package."
  (apply #'make-instance (%ab-sym "ACTIVITY-BUFFER") args))

(test activity-buffer-creation
  "Creating an activity-buffer should succeed with defaults."
  (let ((buf (%make-ab)))
    (is (= 0 (funcall (%ab-sym "CURRENT-SIZE") buf)))
    (is (not (funcall (%ab-sym "IS-FULL-P") buf)))))

(test activity-buffer-creation-custom-max
  "Creating an activity-buffer with a custom max-items."
  (let ((buf (%make-ab :max-items 5)))
    (is (= 5 (funcall (%ab-sym "MAX-ITEMS") buf)))))

(test activity-buffer-upsert-and-get
  "Upserting an activity and retrieving it."
  (let ((buf (%make-ab)))
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "task-1" :repo-id "repo-1" :worktree-id "wt-1"
             :branch "main" :description "Testing")
    (is (= 1 (funcall (%ab-sym "CURRENT-SIZE") buf)))
    (let ((entry (funcall (%ab-sym "GET-ACTIVITY") buf
                          :task-id "task-1" :repo-id "repo-1"
                          :worktree-id "wt-1")))
      (is (not (null entry))))))

(test activity-buffer-upsert-updates-existing
  "Upserting with the same key should update, not add a new entry."
  (let ((buf (%make-ab)))
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1"
             :description "first")
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1"
             :description "second")
    (is (= 1 (funcall (%ab-sym "CURRENT-SIZE") buf)))))

(test activity-buffer-full-signals
  "Buffer must signal an error when full and a new entry is added."
  (let ((buf (%make-ab :max-items 1)))
    ;; Fill to capacity
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1")
    ;; New distinct entry must fail
    (signals error
      (funcall (%ab-sym "UPSERT-ACTIVITY") buf
               :task-id "t2" :repo-id "r2" :worktree-id "w2"))))

(test activity-buffer-remove
  "Removing an activity should decrease the size."
  (let ((buf (%make-ab)))
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1")
    (funcall (%ab-sym "REMOVE-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1")
    (is (= 0 (funcall (%ab-sym "CURRENT-SIZE") buf)))))

(test activity-buffer-clear-all
  "clear-all should remove all entries and return the count."
  (let ((buf (%make-ab)))
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1")
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t2" :repo-id "r2" :worktree-id "w2")
    (let ((removed (funcall (%ab-sym "CLEAR-ALL") buf)))
      (is (= 2 removed))
      (is (= 0 (funcall (%ab-sym "CURRENT-SIZE") buf))))))

(test activity-buffer-list-activities-filter-by-task
  "list-activities with :task-id should filter correctly."
  (let ((buf (%make-ab)))
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t1" :repo-id "r1" :worktree-id "w1")
    (funcall (%ab-sym "UPSERT-ACTIVITY") buf
             :task-id "t2" :repo-id "r1" :worktree-id "w2")
    (let ((results (funcall (%ab-sym "LIST-ACTIVITIES") buf :task-id "t1")))
      (is (= 1 (length results))))))


;;; =======================================================================
;;;  5. Client Stubs
;;; =======================================================================
;;;
;;; The handoff-client and workflow-client inherit from base-client and all
;;; RPC methods signal rpc-error with code "UNIMPLEMENTED". We verify that
;;; instantiation succeeds and methods signal the expected condition.

(def-suite client-stubs-suite
  :description "Client stub instantiation and error signaling tests"
  :in sw4rm-suite)
(in-suite client-stubs-suite)

;; -- base-client ----------------------------------------------------------

(test base-client-creation
  "Creating a base-client with an address should succeed."
  (let ((c (make-instance 'sw4rm::base-client
                           :address "localhost:50051")))
    (is (string= "localhost:50051" (sw4rm::client-address c)))
    (is (= 30000 (sw4rm::client-timeout-ms c)))
    (is (= 3 (sw4rm::client-retry-max-attempts c)))
    (is (null (sw4rm::client-channel c)))))

(test base-client-connect-disconnect
  "connect and disconnect should manage the channel placeholder."
  (let ((c (make-instance 'sw4rm::base-client
                           :address "localhost:50051")))
    (sw4rm::connect c)
    (is (not (null (sw4rm::client-channel c))))
    (sw4rm::disconnect c)
    (is (null (sw4rm::client-channel c)))))

(test base-client-ensure-connected-auto-connects
  "ensure-connected must auto-connect a disconnected client."
  (let ((c (make-instance 'sw4rm::base-client
                           :address "localhost:50051")))
    (sw4rm::ensure-connected c)
    (is (not (null (sw4rm::client-channel c))))))

(test base-client-make-metadata
  "make-metadata must produce a proper alist."
  (let* ((c (make-instance 'sw4rm::base-client
                            :address "localhost:50051"))
         (md (sw4rm::make-metadata c :agent-id "a1" :correlation-id "c1")))
    (is (string= "a1" (cdr (assoc :agent-id md))))
    (is (string= "c1" (cdr (assoc :correlation-id md))))))

;; -- handoff-client -------------------------------------------------------

(test handoff-client-creation
  "Creating a handoff-client should succeed."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (is (typep c 'sw4rm::handoff-client))
    (is (typep c 'sw4rm::base-client))))

(test handoff-initiate-signals-rpc-error
  "initiate-handoff must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::initiate-handoff c '(:from-agent "a" :to-agent "b"))
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test handoff-accept-signals-rpc-error
  "accept-handoff must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::accept-handoff c "handoff-123")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test handoff-reject-signals-rpc-error
  "reject-handoff must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::reject-handoff c "handoff-123" "no capacity")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test handoff-complete-signals-rpc-error
  "complete-handoff must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::complete-handoff c "handoff-123")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test handoff-get-pending-signals-rpc-error
  "get-pending must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::get-pending c "agent-1")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test handoff-get-status-signals-rpc-error
  "get-handoff-status must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::handoff-client
                           :address "localhost:50070")))
    (handler-case
        (progn
          (sw4rm::get-handoff-status c "handoff-123")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

;; -- workflow-client ------------------------------------------------------

(test workflow-client-creation
  "Creating a workflow-client should succeed."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (is (typep c 'sw4rm::workflow-client))
    (is (typep c 'sw4rm::base-client))))

(test workflow-submit-dag-signals-rpc-error
  "submit-dag must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (handler-case
        (progn
          (sw4rm::submit-dag c '(:workflow-id "wf-1" :name "test"))
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test workflow-get-status-signals-rpc-error
  "get-workflow-status must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (handler-case
        (progn
          (sw4rm::get-workflow-status c "wf-1")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test workflow-cancel-signals-rpc-error
  "cancel-workflow must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (handler-case
        (progn
          (sw4rm::cancel-workflow c "wf-1" "abort")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test workflow-resume-signals-rpc-error
  "resume-workflow must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (handler-case
        (progn
          (sw4rm::resume-workflow c "wf-1" "node-1")
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))

(test workflow-list-signals-rpc-error
  "list-workflows must signal rpc-error with UNIMPLEMENTED code."
  (let ((c (make-instance 'sw4rm::workflow-client
                           :address "localhost:50071")))
    (handler-case
        (progn
          (sw4rm::list-workflows c :status :running)
          (fail "Expected rpc-error to be signaled"))
      (sw4rm::rpc-error (e)
        (is (string= "UNIMPLEMENTED" (sw4rm::rpc-error-code e)))))))


;;; =======================================================================
;;;  6. Error Condition Hierarchy
;;; =======================================================================

(def-suite errors-suite :description "Error condition hierarchy tests"
  :in sw4rm-suite)
(in-suite errors-suite)

(test sw4rm-error-is-error
  "sw4rm-error must be a subtype of CL:ERROR."
  (is (subtypep 'sw4rm::sw4rm-error 'error)))

(test validation-error-inherits-sw4rm-error
  "validation-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::validation-error 'sw4rm::sw4rm-error)))

(test state-transition-error-inherits-sw4rm-error
  "state-transition-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::state-transition-error 'sw4rm::sw4rm-error)))

(test timeout-error-inherits-sw4rm-error
  "timeout-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::timeout-error 'sw4rm::sw4rm-error)))

(test buffer-full-error-inherits-sw4rm-error
  "buffer-full-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::buffer-full-error 'sw4rm::sw4rm-error)))

(test negotiation-error-inherits-sw4rm-error
  "negotiation-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::negotiation-error 'sw4rm::sw4rm-error)))

(test worktree-error-inherits-sw4rm-error
  "worktree-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::worktree-error 'sw4rm::sw4rm-error)))

(test duplicate-detected-error-inherits-sw4rm-error
  "duplicate-detected-error must inherit from sw4rm-error."
  (is (subtypep 'sw4rm::duplicate-detected-error 'sw4rm::sw4rm-error)))

(test validation-error-construction
  "Constructing a validation-error should store field and constraint."
  (let ((e (make-condition 'sw4rm::validation-error
                           :message "bad field"
                           :field "agent-id"
                           :constraint "must be non-empty")))
    (is (string= "bad field" (sw4rm::sw4rm-error-message e)))
    (is (string= "agent-id" (sw4rm::validation-error-field e)))
    (is (string= "must be non-empty" (sw4rm::validation-error-constraint e)))
    (is (= sw4rm::+validation-error+ (sw4rm::sw4rm-error-error-code e)))))

(test timeout-error-construction
  "Constructing a timeout-error should store operation and timeout-ms."
  (let ((e (make-condition 'sw4rm::timeout-error
                           :message "timed out"
                           :operation "send-message"
                           :timeout-ms 10000)))
    (is (string= "send-message" (sw4rm::timeout-error-operation e)))
    (is (= 10000 (sw4rm::timeout-error-timeout-ms e)))
    (is (= sw4rm::+ack-timeout+ (sw4rm::sw4rm-error-error-code e)))))


;;; =======================================================================
;;;  Done. Switch back to top-level suite for runner convenience.
;;; =======================================================================

(in-suite sw4rm-suite)
