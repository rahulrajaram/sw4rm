;;;; run-codec-tests.lisp — Standalone codec round-trip tests
;;;;
;;;; Runs without Quicklisp/FiveAM. Loads only the protobuf-codec and
;;;; verifies encode/decode round-trips for all services.
;;;;
;;;; Usage:  sbcl --load test/run-codec-tests.lisp
;;;;
;;;; Exit code 0 = all pass, 1 = failure.

;;; Shim for babel (string↔octets in UTF-8) — must be created before sw4rm-sdk
(defpackage #:babel
  (:use #:cl)
  (:export #:string-to-octets #:octets-to-string))

(in-package #:babel)

(defun string-to-octets (string &key (encoding :utf-8))
  (declare (ignore encoding))
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun octets-to-string (octets &key (encoding :utf-8))
  (declare (ignore encoding))
  (sb-ext:octets-to-string octets :external-format :utf-8))

;;; Minimal sw4rm-sdk package
(defpackage #:sw4rm-sdk
  (:use #:cl))

(in-package #:sw4rm-sdk)

;;; Load codec — resolve relative to the test file's directory (test/ → parent)
(let* ((test-dir (make-pathname :directory (pathname-directory *load-truename*)))
       (sdk-dir  (merge-pathnames (make-pathname :directory '(:relative :up)) test-dir)))
  (load (merge-pathnames "src/transport/protobuf-codec.lisp" sdk-dir)))

;;; Simple test framework
(defvar *test-count* 0)
(defvar *pass-count* 0)
(defvar *fail-count* 0)
(defvar *failures* nil)

(defmacro deftest (name &body body)
  `(progn
     (incf *test-count*)
     (handler-case
         (progn ,@body
                (incf *pass-count*)
                (format t "  PASS  ~A~%" ',name))
       (error (c)
         (incf *fail-count*)
         (push (cons ',name c) *failures*)
         (format t "  FAIL  ~A: ~A~%" ',name c)))))

(defmacro check (expr &optional msg)
  `(unless ,expr
     (error "Assertion failed~@[: ~A~]~%  Form: ~S" ,msg ',expr)))

(defmacro check= (a b &optional msg)
  `(let ((va ,a) (vb ,b))
     (unless (equal va vb)
       (error "~@[~A: ~]Expected ~S, got ~S" ,msg vb va))))

;;; =====================================================================
;;;  Tests
;;; =====================================================================

(format t "~%=== SW4RM Codec Round-Trip Tests ===~%~%")

;;; --- 1. Varint ---
(format t "-- Varint --~%")

(deftest varint-zero
  (let ((enc (encode-varint 0)))
    (check= (length enc) 1)
    (check= (aref enc 0) 0)))

(deftest varint-small
  (let ((enc (encode-varint 42)))
    (check= (length enc) 1)
    (check= (aref enc 0) 42)))

(deftest varint-128
  (let ((enc (encode-varint 128)))
    (check= (length enc) 2)
    (check= (aref enc 0) #x80)
    (check= (aref enc 1) #x01)))

(deftest varint-roundtrip
  (dolist (val '(0 1 42 127 128 255 256 300 16383 16384 65535
                 100000 268435455 4294967295))
    (let ((enc (encode-varint val)))
      (multiple-value-bind (decoded _) (decode-varint enc 0)
        (declare (ignore _))
        (check= decoded val)))))

;;; --- 2. Field encoders ---
(format t "~%-- Field Encoders --~%")

(deftest field-varint
  (let ((f (encode-field-varint 1 42)))
    ;; tag = (1<<3)|0 = 8, val = 42
    (check= (aref f 0) 8)
    (check= (aref f 1) 42)))

(deftest field-string
  (let ((f (encode-field-string 2 "hi")))
    ;; tag = (2<<3)|2 = 18, len = 2, h=104, i=105
    (check= (aref f 0) 18)
    (check= (aref f 1) 2)
    (check= (aref f 2) 104)
    (check= (aref f 3) 105)))

(deftest field-double-roundtrip
  (dolist (val '(0.0d0 1.0d0 0.85d0 -1.5d0))
    (let* ((f (encode-field-double 3 val))
           (fields (if f (decode-fields f) nil)))
      (if (zerop val)
          (check (null f))
          (check (< (abs (- (field-double fields 3 0.0d0) val)) 1d-12)))))
  (let* ((nan-bytes (make-array 8 :element-type '(unsigned-byte 8)
                                :initial-contents '(0 0 0 0 0 0 #xF8 #x7F)))
         (fields (list (cons 3 nan-bytes)))
         (decoded (field-double fields 3 0.0d0)))
    (check (sb-ext:float-nan-p decoded))))

;;; --- 3. decode-fields ---
(format t "~%-- Decode Fields --~%")

(deftest decode-fields-basic
  ;; Build: field 1 varint 42, field 2 string "hi"
  (let* ((f1 (encode-field-varint 1 42))
         (f2 (encode-field-string 2 "hi"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (fields (decode-fields buf)))
    (check= (cdr (assoc 1 fields)) 42)
    (let ((f2-val (cdr (assoc 2 fields))))
      (check (typep f2-val '(simple-array (unsigned-byte 8) (*))))
      ;; "hi" = #(104 105)
      (check= (aref f2-val 0) 104)
      (check= (aref f2-val 1) 105))))

;;; --- 4. Envelope round-trip ---
(format t "~%-- Envelope --~%")

(deftest envelope-roundtrip
  ;; Envelope uses :producer-id not :from-agent at wire level
  (let* ((env (list :message-id "msg-1"
                    :correlation-id "corr-1"
                    :producer-id "agent-a"
                    :message-type 1
                    :payload (make-array 3 :element-type '(unsigned-byte 8)
                                           :initial-contents '(10 20 30))))
         (encoded (encode-envelope env))
         (decoded (decode-envelope encoded)))
    (check (stringp (getf decoded :message-id)))
    (check= (getf decoded :message-id) "msg-1")
    (check= (getf decoded :producer-id) "agent-a")
    (check= (getf decoded :correlation-id) "corr-1")
    (check= (getf decoded :message-type) 1)))

(deftest envelope-decode-default-sequence-number
  (let* ((env (list :message-id "msg-default-seq"
                    :producer-id "agent-a"
                    :message-type 1
                    :payload #()))
         (encoded (encode-envelope env))
         (decoded (decode-envelope encoded)))
    (check= (getf decoded :sequence-number) 0)))

;;; --- 5. Registry ---
(format t "~%-- Registry --~%")

(deftest register-roundtrip
  ;; encode-register-agent-request takes an agent-descriptor plist
  (let* ((desc (list :agent-id "agent-x" :name "my-svc" :description "test"))
         (encoded (encode-register-agent-request desc))
         (fields (decode-fields encoded)))
    ;; field 1 = AgentDescriptor submessage
    (check (assoc 1 fields))))

(deftest heartbeat-roundtrip
  ;; encode-heartbeat-request requires (agent-id state)
  (let* ((encoded (encode-heartbeat-request "agent-x" 4))  ;; 4 = RUNNING
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; agent_id
    (check (assoc 2 fields)))) ;; state

;;; --- 6. Router ---
(format t "~%-- Router --~%")

(deftest route-request-roundtrip
  ;; encode-send-message-request wraps envelope
  (let* ((env (list :message-id "m1" :producer-id "a"
                    :message-type 1 :payload #()))
         (encoded (encode-send-message-request env))
         (fields (decode-fields encoded)))
    ;; field 1 = envelope submessage
    (check (assoc 1 fields))))

;;; --- 7. Scheduler ---
(format t "~%-- Scheduler --~%")

(deftest submit-task-roundtrip
  (let* ((encoded (encode-submit-task-request "agent-1" "task-42"
                   :priority 3 :scope "security-review"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; agent_id
    (check (assoc 2 fields)))) ;; task_id

(deftest submit-task-negative-priority-sign-extends-to-64bit
  (let* ((encoded (encode-submit-task-request "agent-1" "task-neg"
                   :priority -1))
         (fields (decode-fields encoded))
         (priority (field-int fields 3 0)))
    (check (> priority (ash 1 32)))
    (check= priority (1- (ash 1 64)))))

(deftest preempt-roundtrip
  (let* ((encoded (encode-preempt-request "agent-1" "task-42" "urgent"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))
    (check (assoc 3 fields))))

(deftest cancel-task-roundtrip
  (let* ((encoded (encode-cancel-task-request "agent-1" "task-42" "User cancelled"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; agent_id
    (check (assoc 2 fields))   ;; task_id
    (check (assoc 3 fields))))  ;; reason

(deftest get-task-status-encodes-query
  (let* ((encoded (encode-get-task-status-request "agent-1" "task-42"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

(deftest poll-activity-roundtrip
  (let* ((encoded (encode-poll-activity-buffer-request "agent-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest purge-activity-roundtrip
  (let* ((encoded (encode-purge-activity-request "agent-1" '("t1" "t2")))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; agent_id
    (check (assoc 2 fields)))) ;; task_ids (repeated)

(deftest shutdown-agent-encodes-grace-period
  (let* ((encoded (encode-shutdown-agent-request "agent-1" 5 0))
         (fields (decode-fields encoded))
         (duration (field-bytes fields 2))
         (duration-fields (decode-fields duration)))
    (check= (field-string fields 1) "agent-1")
    (check= (field-int duration-fields 1 0) 5)))

;;; --- 8. Tool ---
(format t "~%-- Tool --~%")

(deftest tool-call-roundtrip
  ;; ToolCall fields: 1=call_id, 2=tool_name, 3=provider_id, 4=content_type, 5=args
  (let* ((call-plist (list :call-id "call-1"
                           :tool-name "read_file"
                           :provider-id "prov-1"
                           :args "{\"path\":\"/tmp/f\"}"))
         (encoded (encode-tool-call call-plist))
         (fields (decode-fields encoded)))
  (check (assoc 1 fields))   ;; call_id
  (check (assoc 2 fields))   ;; tool_name
  (check (assoc 3 fields)))) ;; provider_id

(deftest list-tools-request-roundtrip
  (let* ((encoded (encode-list-tools-request "prov-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest list-tools-response-roundtrip
  (let* ((descriptor-1 (encode-tool-descriptor
                        (list :tool-name "read_file"
                              :input-schema "{\"type\":\"object\"}"
                              :idempotent t))
                       )
         (descriptor-2 (encode-tool-descriptor
                        (list :tool-name "write_file"
                              :input-schema "{\"type\":\"object\"}"
                              :output-schema "{\"type\":\"string\"}"
                              :idempotent nil))
                       )
         (encoded (concatenate '(simple-array (unsigned-byte 8) (*))
                              (encode-field-submessage 1 descriptor-1)
                              (encode-field-submessage 1 descriptor-2)))
         (result (decode-list-tools-response encoded)))
    (check (= (length result) 2))
    (check= (getf (first result) :tool-name) "read_file")
    (check= (getf (second result) :tool-name) "write_file")))

;;; --- 9. HITL ---
(format t "~%-- HITL --~%")

(deftest hitl-invocation-roundtrip
  ;; HitlInvocation: 1=reason_type(varint), 2=context(bytes), 3=proposed_actions, 4=priority
  (let* ((inv (list :reason-type 1
                    :context "security check"
                    :proposed-actions '("approve" "reject")
                    :priority 2))
         (encoded (encode-hitl-invocation inv))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; reason_type
    (check (assoc 2 fields)))) ;; context

(deftest hitl-response-request-roundtrip
  (let* ((encoded (encode-hitl-response-request "decision-1" "approve" "Looks safe"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; decision_id
    (check (assoc 2 fields))   ;; selected_option
    (check (assoc 3 fields)))) ;; notes

(deftest hitl-pending-request-roundtrip
  (let* ((encoded (encode-hitl-pending-request "operator-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest hitl-decision-status-request-roundtrip
  (let* ((encoded (encode-hitl-decision-status-request "decision-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

;;; --- 10. Logging ---
(format t "~%-- Logging --~%")

(deftest log-event-roundtrip
  ;; LogEvent: field 1=Timestamp(skip), 2=correlation_id, 3=agent_id, 4=event_type, 5=level, 6=details
  (let* ((ev (list :agent-id "agent-1"
                   :message "Something happened"
                   :correlation-id "corr-1"))
         (encoded (encode-log-event ev))
         (fields (decode-fields encoded)))
    ;; field 2 = correlation_id, field 3 = agent_id (field 1 = Timestamp, skipped)
    (check (assoc 2 fields))
    (check (assoc 3 fields))))

(deftest query-logs-request-roundtrip
  (let* ((encoded (encode-query-logs-request
                    :correlation-id "corr-1"
                    :agent-id "agent-1"
                    :level :error
                    :start-time "2026-02-01T00:00:00Z"
                    :end-time "2026-02-01T01:00:00Z"
                    :tags '("security" "api")
                    :limit 50))
         (fields (decode-fields encoded)))
    (check (assoc 2 fields))
    (check (assoc 3 fields))
    (check (assoc 4 fields))
    (check (assoc 5 fields))
    (check (= (length (field-repeated-strings fields 7) ) 2))
    (check (assoc 8 fields))))

;;; --- 11. Connector ---
(format t "~%-- Connector --~%")

(deftest tool-descriptor-roundtrip
  (let* ((desc (list :tool-name "read_file"
                     :input-schema "{\"type\":\"object\"}"
                     :idempotent t))
         (encoded (encode-tool-descriptor desc))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; tool_name
    (check (assoc 2 fields))))  ;; input_schema

(deftest provider-register-roundtrip
  ;; tools arg is a list of plists — encode-provider-register-request calls encode-tool-descriptor
  (let* ((tool-plist (list :tool-name "read_file"
                           :input-schema "{}"))
         (encoded (encode-provider-register-request "prov-1" (list tool-plist)))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; provider_id
    (check (assoc 2 fields))))  ;; tools (repeated submessage)

(deftest describe-tools-roundtrip
  (let* ((encoded (encode-describe-tools-request "prov-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest list-providers-request-roundtrip
  (let* ((encoded (encode-list-providers-request)))
    (check= (length encoded) 0)))

(deftest list-providers-response-roundtrip
  (let* ((entry (concatenate '(simple-array (unsigned-byte 8) (*))
                             (encode-field-string 1 "provider-1")
                             (encode-field-string 2 "2026-02-01T00:00:00Z")
                             (encode-field-varint 3 4)))
         (encoded (encode-field-submessage 1 entry))
         (result (decode-list-providers-response encoded)))
    (check (= (length result) 1))
    (check= (getf (first result) :provider-id) "provider-1")
    (check= (getf (first result) :tool-count) 4)))

;;; --- 12. Worktree ---
(format t "~%-- Worktree --~%")

(deftest bind-roundtrip
  (let* ((encoded (encode-bind-request "agent-1" "repo-1" "wt-main"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))
    (check (assoc 3 fields))))

(deftest unbind-roundtrip
  (let* ((encoded (encode-unbind-request "agent-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest switch-request-roundtrip
  (let* ((encoded (encode-switch-request "agent-1" "wt-feature"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

;;; --- 13. Activity ---
(format t "~%-- Activity --~%")

(deftest artifact-roundtrip
  ;; Artifact: 1=negotiation_id, 2=kind, 3=version, 4=content_type, 5=content, 6=created_at
  (let* ((art (list :negotiation-id "neg-1"
                    :kind "code"
                    :content-type "text/plain"
                    :content (make-array 5 :element-type '(unsigned-byte 8)
                                           :initial-contents '(72 101 108 108 111))))
         (encoded (encode-artifact art))
         (decoded (decode-artifact encoded)))
    (check= (getf decoded :negotiation-id) "neg-1")
    (check= (getf decoded :kind) "code")
    (check= (getf decoded :content-type) "text/plain")))

(deftest append-artifact-roundtrip
  (let* ((art (list :negotiation-id "neg-2"
                    :kind "doc"))
         (encoded (encode-append-artifact-request art))
         (fields (decode-fields encoded)))
    ;; field 1 = submessage (Artifact)
    (check (assoc 1 fields))))

(deftest list-artifacts-roundtrip
  (let* ((encoded (encode-list-artifacts-request "neg-1" "code"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; negotiation_id
    (check (assoc 2 fields))))  ;; kind filter

(deftest deregister-artifact-request-roundtrip
  (let* ((encoded (encode-deregister-activity-request "artifact-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest get-artifact-request-roundtrip
  (let* ((encoded (encode-get-artifact-request "artifact-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

;;; --- 14. Negotiation ---
(format t "~%-- Negotiation --~%")

(deftest negotiation-open-roundtrip
  (let* ((neg (list :negotiation-id "neg-1"
                    :correlation-id "corr-1"
                    :topic "API design"
                    :participants '("agent-1" "agent-2")
                    :intensity 2))
         (encoded (encode-negotiation-open neg))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; negotiation_id
    (check (assoc 3 fields)))) ;; topic

(deftest proposal-roundtrip
  (let* ((prop (list :negotiation-id "neg-1"
                     :from-agent "agent-1"
                     :content-type "application/json"
                     :payload (make-array 2 :element-type '(unsigned-byte 8)
                                            :initial-contents '(123 125))))
         (encoded (encode-proposal prop))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; negotiation_id
    (check (assoc 2 fields)))) ;; from_agent

(deftest decision-roundtrip
  (let* ((dec (list :negotiation-id "neg-1"
                    :decided-by "coordinator"
                    :content-type "application/json"
                    :result (make-array 2 :element-type '(unsigned-byte 8)
                                          :initial-contents '(123 125))))
         (encoded (encode-decision dec))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

(deftest evaluation-encodes-confidence-score-double
  (let* ((encoded (encode-evaluation
                   (list :negotiation-id "neg-1"
                         :from-agent "agent-1"
                         :confidence-score 0.85d0
                         :notes "looks good")))
         (fields (decode-fields encoded)))
    (check (assoc 3 fields))
    (check (< (abs (- (field-double fields 3 0.0d0) 0.85d0)) 1d-12))))

(deftest abort-roundtrip
  (let* ((encoded (encode-abort-request "neg-1" "cancelled"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

(deftest get-session-request-roundtrip
  (let* ((encoded (encode-get-session-request "neg-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest get-session-response-roundtrip
  (let* ((proposal-1 (encode-proposal (list :negotiation-id "neg-1"
                                            :from-agent "agent-1"
                                            :content-type "application/json"
                                            :payload (make-array 0 :element-type '(unsigned-byte 8))))
                                      )
         (proposal-2 (encode-proposal (list :negotiation-id "neg-1"
                                            :from-agent "agent-2"
                                            :content-type "text/plain"
                                            :payload (make-array 0 :element-type '(unsigned-byte 8))))
                                      )
         (evaluation (encode-evaluation (list :negotiation-id "neg-1"
                                             :from-agent "judge"
                                             :confidence-score 0.91d0
                                             :notes "ok"))
                      )
         (decision (encode-decision (list :negotiation-id "neg-1"
                                         :decided-by "coordinator"
                                         :content-type "text/json"
                                         :result (make-array 0 :element-type '(unsigned-byte 8))))
                                 )
         (response (concatenate '(simple-array (unsigned-byte 8) (*))
                               (encode-field-string 1 "neg-1")
                               (encode-field-varint 2 1)
                               (encode-field-string 3 "agent-1")
                               (encode-field-string 3 "agent-2")
                               (encode-field-submessage 4 proposal-1)
                               (encode-field-submessage 4 proposal-2)
                               (encode-field-submessage 5 evaluation)
                               (encode-field-submessage 6 decision)))
         (result (decode-get-session-response response)))
    (check= (getf result :negotiation-id) "neg-1")
    (check= (getf result :status) 1)
    (check= (length (getf result :participants)) 2)
    (check (= (length (getf result :proposals)) 2))
    (check (= (length (getf result :evaluations)) 1))))

;;; --- 15. Reasoning ---
(format t "~%-- Reasoning --~%")

(deftest parallelism-check-roundtrip
  (let* ((encoded (encode-parallelism-check-request "scope A" "scope B"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

(deftest debate-evaluate-roundtrip
  (let* ((encoded (encode-debate-evaluate-request "neg-1" "proposal A" "proposal B" "high"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; negotiation_id
    (check (assoc 2 fields))   ;; proposal_a
    (check (assoc 3 fields)))) ;; proposal_b

(deftest summarize-request-roundtrip
  ;; segments are plists — encode-summarize-request calls encode-text-segment internally
  (let* ((seg1 (list :kind "user"
                     :content "Hello"
                     :seq 1
                     :at "2026-01-01T00:00:00Z"))
         (encoded (encode-summarize-request "sess-1" (list seg1)
                                            :max-tokens 128 :mode "full"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; session_id
    (check (assoc 2 fields))))  ;; segments (repeated submessage)

;;; --- 16. Workflow ---
(format t "~%-- Workflow --~%")

(deftest create-workflow-roundtrip
  (let* ((def (list :workflow-id "wf-1"
                    :nodes (list
                            (cons "node-1"
                                  (list :node-id "node-1"
                                        :agent-id "agent-1"
                                        :dependencies '("seed-1" "seed-2")
                                        :trigger-type :event
                                        :input-mapping '(("topic" . "in")
                                                        ("mode" . "batch"))
                                        :output-mapping '(("result" . "out"))
                                        :metadata '(("priority" . "high"))))
                            (cons "node-2"
                                  (list :node-id "node-2"
                                        :agent-id "agent-2"
                                        :trigger-type :schedule
                                        :dependencies '("node-1")
                                        :input-mapping '(("in" . "result")))))
                    :created-at "2026-02-20T10:00:00Z"
                    :metadata '(("name" . "Test Workflow")
                               ("owner" . "qa"))))
         (encoded (encode-create-workflow-request def))
         (req-fields (decode-fields encoded))
         (decoded (decode-workflow-definition (field-bytes req-fields 1))))
    (check (assoc 1 req-fields))
    (check= (getf decoded :workflow-id) "wf-1")
    (check= (length (getf decoded :nodes)) 2)
    (let ((node-2 (cdr (assoc "node-2" (getf decoded :nodes) :test #'string=))))
      (check= (getf node-2 :node-id) "node-2")
      (check= (getf node-2 :agent-id) "agent-2")
      (check= (getf node-2 :trigger-type) :schedule)
      (check (equal (getf node-2 :dependencies) '("node-1"))))))

(deftest workflow-state-response-roundtrip
  (let* ((node-state (list :node-id "node-1"
                           :status :running
                           :started-at "2026-02-20T10:00:10Z"
                           :output "{\"ok\":true}"
                           :error ""))
         (workflow-state (list :workflow-id "wf-1"
                               :node-states (list (cons "node-1" node-state))
                               :workflow-data "{\"stage\":\"running\"}"
                               :started-at "2026-02-20T10:00:00Z"
                               :completed-at ""
                               :metadata '(("phase" . "run"))))
         (workflow-bytes (encode-workflow-state workflow-state))
         (start-response (concatenate '(simple-array (unsigned-byte 8) (*))
                                    (encode-field-string 1 "wf-1")
                                    (encode-field-submessage 2 workflow-bytes)
                                    (encode-field-varint 3 1)
                                    (encode-field-string 4 "")))
         (get-response (concatenate '(simple-array (unsigned-byte 8) (*))
                                   (encode-field-submessage 1 workflow-bytes)
                                   (encode-field-varint 2 1)
                                   (encode-field-string 3 "")))
         (resume-response (concatenate '(simple-array (unsigned-byte 8) (*))
                                      (encode-field-string 1 "wf-1")
                                      (encode-field-submessage 2 workflow-bytes)
                                      (encode-field-varint 3 1)
                                      (encode-field-string 4 "")))
         (start-result (decode-start-workflow-response start-response))
         (get-result (decode-get-workflow-state-response get-response))
         (resume-result (decode-resume-workflow-response resume-response)))
    (check= (getf start-result :success) t)
    (check= (getf get-result :success) t)
    (check= (getf resume-result :success) t)
    (check= (getf (getf start-result :state) :workflow-id) "wf-1")
    (check= (getf (getf get-result :state) :workflow-id) "wf-1")
    (check= (getf (getf resume-result :state) :workflow-id) "wf-1")
    (let ((node (cdr (assoc "node-1" (getf (getf start-result :state) :node-states)
                            :test #'string=))))
      (check= (getf node :status) :running)
      (check= (getf node :node-id) "node-1"))))

(deftest get-workflow-state-roundtrip
  (let* ((encoded (encode-get-workflow-state-request "wf-1"))
        (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest resume-workflow-roundtrip
  (let* ((encoded (encode-resume-workflow-request "wf-1" "node-1"
                   :workflow-data "{\"status\":\"ok\"}"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

;;; --- 17. Scheduler Policy ---
(format t "~%-- Scheduler Policy --~%")

(deftest get-negotiation-policy-roundtrip
  (let* ((encoded (encode-get-negotiation-policy-request)))
    (check (typep encoded '(simple-array (unsigned-byte 8) (*))))))

(deftest set-negotiation-policy-roundtrip
  (let* ((policy (list :max-rounds 12
                       :score-threshold 0.75
                       :diff-tolerance 0.15
                       :round-timeout-ms 2000
                       :token-budget-per-round 500
                       :total-token-budget 5000
                       :oscillation-limit 2
                       :hitl (list :mode "PauseBetweenRounds")
                       :scoring (list :require-schema-valid t
                                      :require-examples-pass nil
                                      :llm-weight 0.35)))
         (encoded (encode-set-negotiation-policy-request policy))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest get-effective-policy-roundtrip
  (let* ((encoded (encode-get-effective-policy-request "neg-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest decode-get-negotiation-policy-response-roundtrip
  (let* ((policy (list :max-rounds 12
                       :score-threshold 0.75
                       :diff-tolerance 0.15))
         (payload (encode-field-submessage 1 (encode-negotiation-policy policy)))
         (result (decode-get-negotiation-policy-response payload)))
    (check= (getf (getf result :policy) :max-rounds) 12)
    (check= (getf (getf result :policy) :score-threshold) 0.75)))

(deftest decode-list-policy-profiles-response-roundtrip
  (let* ((profile-1 (encode-policy-profile
                     (list :name "LOW"
                           :policy (list :max-rounds 3
                                         :score-threshold 0.4
                                         :diff-tolerance 0.05))))
         (profile-2 (encode-policy-profile
                     (list :name "HIGH"
                           :policy (list :max-rounds 15
                                         :score-threshold 0.9
                                         :diff-tolerance 0.2))))
         (payload (concatenate '(simple-array (unsigned-byte 8) (*))
                               (encode-field-submessage 1 profile-1)
                               (encode-field-submessage 1 profile-2)))
         (result (decode-list-policy-profiles-response payload)))
    (check= (length result) 2)
    (check= (getf (first result) :name) "LOW")
    (check= (getf (second result) :name) "HIGH")))

(deftest set-policy-profiles-request-roundtrip
  (let* ((profiles (list (list :name "LOW"
                               :policy (list :max-rounds 3
                                             :score-threshold 0.4
                                             :diff-tolerance 0.05))
                         (list :name "MEDIUM"
                               :policy (list :max-rounds 8
                                             :score-threshold 0.7
                                             :diff-tolerance 0.1))))
         (encoded (encode-set-policy-profiles-request profiles))
         (fields (decode-fields encoded)))
    (check (= (length fields) 2))
    (check (assoc 1 fields))
    (check (typep (cdr (assoc 1 fields)) '(simple-array (unsigned-byte 8) (*))))))

(deftest decode-get-effective-policy-response-roundtrip
  (let* ((effective (list :policy (list :max-rounds 6
                                        :score-threshold 0.78
                                        :diff-tolerance 0.12)
                          :applied '(("agent-a" . (:max-rounds 4
                                                   :score-threshold 0.5
                                                   :diff-tolerance 0.1)))))
         (payload (encode-effective-policy effective))
         (response (encode-field-submessage 1 payload))
         (result (decode-get-effective-policy-response response)))
    (check= (getf (getf (getf result :effective) :policy) :max-rounds) 6)
    (let ((agent-override (cdr (assoc "agent-a" (getf (getf result :effective) :applied)
                                       :test #'string=))))
      (check= (getf agent-override :max-rounds) 4))))

(deftest submit-evaluation-roundtrip
  (let* ((report-bytes (make-array 2 :element-type '(unsigned-byte 8)
                                     :initial-contents '(8 1)))
         (encoded (encode-submit-evaluation-request "neg-1" report-bytes))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; negotiation_id
    (check (assoc 2 fields))))  ;; report

(deftest submit-evaluation-request-roundtrip
  (let* ((report (list :from-agent "agent-1"
                       :deterministic-score 0.84
                       :llm-confidence 0.95
                       :notes "good"
                       :delta (list :magnitude 0.23
                                    :changed-paths '("metrics.score"))))
         (encoded (encode-submit-evaluation-request "neg-1" report))
         (fields (decode-fields encoded))
         (decoded-report (decode-policy-evaluation-report
                          (field-bytes fields 2))))
    (check (assoc 1 fields))
    (check (assoc 2 fields))
    (check= (getf decoded-report :from-agent) "agent-1")
    (check= (getf decoded-report :deterministic-score) 0.84)
    (check= (length (getf (getf decoded-report :delta) :changed-paths)) 1)))

(deftest hitl-action-roundtrip
  (let* ((encoded (encode-hitl-action-request "neg-1" "approve" "Looks good"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))
    (check (assoc 3 fields))))

;;; --- 18. Decode response round-trips ---
(format t "~%-- Response Decoders --~%")

(deftest decode-empty-response-test
  ;; Returns T unconditionally
  (let ((result (decode-empty-response #())))
    (check= result t)))

(deftest decode-submit-task-response-test
  ;; SubmitTaskResponse: field 1 = accepted (bool), field 2 = reason (string)
  (let* ((f1 (encode-field-varint 1 1))
         (f2 (encode-field-string 2 "ok"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-submit-task-response buf)))
    (check= (getf result :accepted) t)
    (check= (getf result :reason) "ok")))

(deftest decode-preempt-response-test
  ;; PreemptResponse: field 1 = enqueued (bool)
  (let* ((f1 (encode-field-varint 1 1))
         (buf (coerce (coerce f1 'list) '(simple-array (unsigned-byte 8) (*))))
         (result (decode-preempt-response buf)))
    (check= (getf result :enqueued) t)))

(deftest decode-cancel-task-response-test
  (let* ((f1 (encode-field-varint 1 1))
         (f2 (encode-field-string 2 "cancelled"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-cancel-task-response buf)))
    (check= (getf result :cancelled) t)
    (check= (getf result :reason) "cancelled")))

(deftest decode-task-status-response-test
  (let* ((f1 (encode-field-string 1 "task-1"))
         (f2 (encode-field-varint 2 3))
         (f3 (encode-field-double 3 0.55d0))
         (f4 (encode-field-string 4 "running"))
         (f5 (encode-field-string 5 "2026-02-01T00:00:00Z"))
         (f6 (encode-field-string 6 "2026-02-01T01:00:00Z"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2 f3 f4 f5 f6))
         (result (decode-task-status-response buf)))
    (check= (getf result :task-id) "task-1")
    (check= (getf result :status) 3)
    (check (< (abs (- (getf result :progress) 0.55d0)) 1d-12))
    (check= (getf result :message) "running")
    (check= (getf result :started-at) "2026-02-01T00:00:00Z")
    (check= (getf result :completed-at) "2026-02-01T01:00:00Z")))

(deftest decode-hitl-response-response-test
  (let* ((f1 (encode-field-varint 1 1))
         (f2 (encode-field-string 2 "accepted"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-hitl-response-response buf)))
    (check= (getf result :recorded) t)
    (check= (getf result :reason) "accepted")))

(deftest decode-hitl-pending-response-test
  (let* ((entry (concatenate '(simple-array (unsigned-byte 8) (*))
                            (encode-field-string 1 "decision-1")
                            (encode-field-string 2 "corr-1")
                            (encode-field-varint 3 4)
                            (encode-field-string 4 "Need review")
                            (encode-field-varint 5 1)
                            (encode-field-string 6 "2026-02-01T00:00:00Z")
                            (encode-field-string 7 "2026-02-01T01:00:00Z")))
         (buf (encode-field-submessage 1 entry))
         (result (decode-hitl-pending-response buf)))
    (check= (length result) 1)
    (check= (getf (first result) :decision-id) "decision-1")
    (check= (getf (first result) :status) 1)))

(deftest decode-hitl-decision-status-response-test
  (let* ((f1 (encode-field-string 1 "decision-1"))
         (f2 (encode-field-varint 2 2))
         (f3 (encode-field-string 3 "approve"))
         (f4 (encode-field-string 4 "notes"))
         (f5 (encode-field-string 5 "2026-02-01T00:00:00Z"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2 f3 f4 f5))
         (result (decode-hitl-decision-status-response buf)))
    (check= (getf result :decision-id) "decision-1")
    (check= (getf result :status) 2)
    (check= (getf result :selected-option) "approve")))

(deftest decode-query-logs-response-test
  (let* ((entry-1 (concatenate '(simple-array (unsigned-byte 8) (*))
                               (encode-field-string 2 "corr-1")
                               (encode-field-string 3 "agent-1")
                               (encode-field-string 4 "event")
                               (encode-field-string 5 "INFO")
                               (encode-field-string 6 "{}")))
         (entry-2 (concatenate '(simple-array (unsigned-byte 8) (*))
                               (encode-field-string 2 "corr-2")
                               (encode-field-string 3 "agent-2")
                               (encode-field-string 4 "event-2")
                               (encode-field-string 5 "WARN")
                               (encode-field-string 6 "{\"x\":1}")))
         (buffer (concatenate '(simple-array (unsigned-byte 8) (*))
                             (encode-field-submessage 1 entry-1)
                             (encode-field-submessage 1 entry-2)))
         (result (decode-query-logs-response buffer)))
    (check= (length result) 2)
    (check= (getf (first result) :agent-id) "agent-1")
    (check= (getf (second result) :level) "WARN")))

(deftest decode-list-providers-response-test
  (let* ((entry (concatenate '(simple-array (unsigned-byte 8) (*))
                             (encode-field-string 1 "provider-1")
                             (encode-field-string 2 "2026-02-01T00:00:00Z")
                             (encode-field-varint 3 4)))
         (buffer (encode-field-submessage 1 entry))
         (result (decode-list-providers-response buffer)))
    (check= (length result) 1)
    (check= (getf (first result) :tool-count) 4)))

(deftest decode-deregister-activity-response-test
  (let* ((f1 (encode-field-varint 1 1))
         (f2 (encode-field-string 2 "removed"))
         (buffer (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-deregister-activity-response buffer)))
    (check= (getf result :ok) t)
    (check= (getf result :reason) "removed")))

(deftest decode-get-artifact-response-test
  (let* ((artifact (encode-artifact (list :negotiation-id "neg-1"
                                         :kind "code"
                                         :version "v1"
                                         :content-type "text/plain"
                                         :content (make-array 3 :element-type '(unsigned-byte 8)
                                                           :initial-contents '(1 2 3))
                                         :created-at "2026-02-01T00:00:00Z")))
         (buffer (encode-field-submessage 1 artifact))
         (result (decode-get-artifact-response buffer)))
    (check= (getf result :negotiation-id) "neg-1")
    (check= (getf result :kind) "code")
    (check= (getf result :version) "v1")))

(deftest decode-list-tools-response-test
  (let* ((descriptor-1 (encode-tool-descriptor
                        (list :tool-name "read_file"
                              :input-schema "{\"type\":\"object\"}"
                              :idempotent t))
                       )
         (descriptor-2 (encode-tool-descriptor
                        (list :tool-name "write_file"
                              :input-schema "{\"type\":\"object\"}"
                              :output-schema "{\"type\":\"string\"}"
                              :idempotent nil))
                       )
         (buffer (concatenate '(simple-array (unsigned-byte 8) (*))
                             (encode-field-submessage 1 descriptor-1)
                             (encode-field-submessage 1 descriptor-2)))
         (result (decode-list-tools-response buffer)))
    (check= (length result) 2)
    (check= (getf (first result) :tool-name) "read_file")
    (check= (getf (second result) :tool-name) "write_file")))

(deftest decode-get-session-response-test
  (let* ((proposal (encode-proposal (list :negotiation-id "neg-1"
                                        :from-agent "agent-1"
                                        :content-type "text/plain"
                                        :payload (make-array 0 :element-type '(unsigned-byte 8))))
                               )
         (evaluation (encode-evaluation (list :negotiation-id "neg-1"
                                             :from-agent "judge"
                                             :confidence-score 0.91d0
                                             :notes "ok"))
                                 )
         (decision (encode-decision (list :negotiation-id "neg-1"
                                         :decided-by "coordinator"
                                         :content-type "text/json"
                                         :result (make-array 0 :element-type '(unsigned-byte 8)))))
         (response (concatenate '(simple-array (unsigned-byte 8) (*))
                               (encode-field-string 1 "neg-1")
                               (encode-field-varint 2 1)
                               (encode-field-string 3 "agent-1")
                               (encode-field-string 3 "agent-2")
                               (encode-field-submessage 4 proposal)
                               (encode-field-submessage 5 evaluation)
                               (encode-field-submessage 6 decision)))
         (result (decode-get-session-response response)))
    (check= (getf result :negotiation-id) "neg-1")
    (check= (getf result :status) 1)
    (check= (length (getf result :participants)) 2)
    (check= (length (getf result :proposals)) 1)
    (check= (length (getf result :evaluations)) 1)))

(deftest decode-ingest-response-test
  ;; IngestResponse: field 1 = ok (bool/varint)
  (let* ((f1 (encode-field-varint 1 1))
         (buf (coerce (coerce f1 'list) '(simple-array (unsigned-byte 8) (*))))
         (result (decode-ingest-response buf)))
    (check= (getf result :ok) t)))

(deftest decode-tool-frame-test
  ;; ToolFrame: 1=call_id, 2=frame_no, 3=final, 4=content_type, 5=data
  (let* ((f1 (encode-field-string 1 "call-1"))
         (f2 (encode-field-varint 2 5))
         (f3 (encode-field-varint 3 1))  ;; final=true
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2 f3))
         (result (decode-tool-frame buf)))
    (check= (getf result :call-id) "call-1")
    (check= (getf result :frame-no) 5)
    (check= (getf result :final) t)))

(deftest decode-hitl-decision-test
  ;; HitlDecision: 1=action, 2=decision_payload, 3=rationale
  (let* ((f1 (encode-field-string 1 "approve"))
         (f3 (encode-field-string 3 "Looks safe"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f3))
         (result (decode-hitl-decision buf)))
    (check= (getf result :action) "approve")
    (check= (getf result :rationale) "Looks safe")))

(deftest decode-parallelism-check-response-test
  ;; ParallelismCheckResponse: 1=confidence_score(double), 2=notes
  (let* ((f1 (encode-field-double 1 0.875d0))
         (f2 (encode-field-string 2 "Independent scopes"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-parallelism-check-response buf)))
    (check (< (abs (- (getf result :confidence-score) 0.875d0)) 1d-12))
    (check= (getf result :notes) "Independent scopes")))

(deftest decode-debate-evaluate-response-test
  (let* ((f1 (encode-field-double 1 0.42d0))
         (f2 (encode-field-string 2 "tie-break leaning A"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2))
         (result (decode-debate-evaluate-response buf)))
    (check (< (abs (- (getf result :confidence-score) 0.42d0)) 1d-12))
    (check= (getf result :notes) "tie-break leaning A")))

(deftest decode-summarize-response-test
  (let* ((f1 (encode-field-string 1 "summary"))
         (f2 (encode-field-varint 2 12))
         (f3 (encode-field-double 3 2.75d0))
         (f4 (encode-field-string 4 "model-x"))
         (buf (concatenate '(simple-array (unsigned-byte 8) (*)) f1 f2 f3 f4))
         (result (decode-summarize-response buf)))
    (check= (getf result :summary) "summary")
    (check= (getf result :tokens) 12)
    (check (< (abs (- (getf result :cost-cents) 2.75d0)) 1d-12))
    (check= (getf result :model) "model-x")))

;;; =====================================================================
;;;  Summary
;;; =====================================================================

(format t "~%=== Results: ~D/~D passed, ~D failed ===~%"
        *pass-count* *test-count* *fail-count*)

(when *failures*
  (format t "~%Failures:~%")
  (dolist (f (reverse *failures*))
    (format t "  ~A: ~A~%" (car f) (cdr f))))

(if (zerop *fail-count*)
    (progn (format t "~%ALL TESTS PASSED~%")
           (sb-ext:exit :code 0))
    (progn (format t "~%SOME TESTS FAILED~%")
           (sb-ext:exit :code 1)))
