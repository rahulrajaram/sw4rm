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

(deftest preempt-roundtrip
  (let* ((encoded (encode-preempt-request "agent-1" "task-42" "urgent"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))
    (check (assoc 3 fields))))

(deftest poll-activity-roundtrip
  (let* ((encoded (encode-poll-activity-buffer-request "agent-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest purge-activity-roundtrip
  (let* ((encoded (encode-purge-activity-request "agent-1" '("t1" "t2")))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))   ;; agent_id
    (check (assoc 2 fields)))) ;; task_ids (repeated)

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

(deftest abort-roundtrip
  (let* ((encoded (encode-abort-request "neg-1" "cancelled"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))
    (check (assoc 2 fields))))

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
                    :name "Test Workflow"))
         (encoded (encode-create-workflow-request def))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

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
  (let* ((policy-bytes (make-array 4 :element-type '(unsigned-byte 8)
                                     :initial-contents '(8 10 16 20)))
         (encoded (encode-set-negotiation-policy-request policy-bytes))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest get-effective-policy-roundtrip
  (let* ((encoded (encode-get-effective-policy-request "neg-1"))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))))

(deftest submit-evaluation-roundtrip
  (let* ((report-bytes (make-array 2 :element-type '(unsigned-byte 8)
                                     :initial-contents '(8 1)))
         (encoded (encode-submit-evaluation-request "neg-1" report-bytes))
         (fields (decode-fields encoded)))
    (check (assoc 1 fields))    ;; negotiation_id
    (check (assoc 2 fields))))  ;; report

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
  ;; ParallelismCheckResponse: 1=confidence_score(double→int fallback), 2=notes
  (let* ((f2 (encode-field-string 2 "Independent scopes"))
         (buf (coerce (coerce f2 'list) '(simple-array (unsigned-byte 8) (*))))
         (result (decode-parallelism-check-response buf)))
    (check= (getf result :notes) "Independent scopes")))

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
