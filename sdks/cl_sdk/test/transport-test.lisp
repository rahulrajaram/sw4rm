;;;; transport-test.lisp — Codec round-trip + FFI smoke tests
;;;;
;;;; Run with:
;;;;   (ql:quickload '(:sw4rm-sdk :fiveam))
;;;;   (load "test/transport-test.lisp")
;;;;   (fiveam:run! 'sw4rm-test::transport-suite)

(in-package :sw4rm-test)

(def-suite transport-suite :description "Transport layer tests"
  :in sw4rm-suite)
(in-suite transport-suite)

;;; =======================================================================
;;;  1. Varint primitives
;;; =======================================================================

(def-suite varint-suite :description "Varint encode/decode" :in transport-suite)
(in-suite varint-suite)

(test varint-zero
  "Encoding 0 yields a single zero byte."
  (let ((encoded (sw4rm-sdk:encode-varint 0)))
    (is (= 1 (length encoded)))
    (is (= 0 (aref encoded 0)))))

(test varint-small
  "Encoding values < 128 yields a single byte."
  (let ((encoded (sw4rm-sdk:encode-varint 42)))
    (is (= 1 (length encoded)))
    (is (= 42 (aref encoded 0)))))

(test varint-128
  "Encoding 128 requires 2 bytes."
  (let ((encoded (sw4rm-sdk:encode-varint 128)))
    (is (= 2 (length encoded)))
    ;; 128 = 0x80 → 0x80 0x01
    (is (= #x80 (aref encoded 0)))
    (is (= #x01 (aref encoded 1)))))

(test varint-300
  "Encoding 300 = 0x012C → 0xAC 0x02."
  (let ((encoded (sw4rm-sdk:encode-varint 300)))
    (is (= 2 (length encoded)))
    (is (= #xAC (aref encoded 0)))
    (is (= #x02 (aref encoded 1)))))

(test varint-roundtrip
  "Encode then decode returns original value."
  (dolist (val '(0 1 42 127 128 255 256 300 16383 16384 65535
                 100000 268435455 4294967295))
    (let ((encoded (sw4rm-sdk:encode-varint val)))
      (multiple-value-bind (decoded new-offset)
          (sw4rm-sdk:decode-varint encoded 0)
        (is (= val decoded)
            "Varint roundtrip failed for ~D: got ~D" val decoded)
        (is (= (length encoded) new-offset))))))

;;; =======================================================================
;;;  2. Field encoder tests
;;; =======================================================================

(def-suite field-suite :description "Field encoding" :in transport-suite)
(in-suite field-suite)

(test field-varint-omits-zero
  "encode-field-varint returns NIL for value 0 (proto3 default)."
  (is (null (sw4rm-sdk:encode-field-varint 1 0))))

(test field-varint-nonzero
  "encode-field-varint encodes tag + varint for non-zero values."
  (let ((encoded (sw4rm-sdk:encode-field-varint 1 42)))
    (is (not (null encoded)))
    (is (> (length encoded) 0))
    ;; Tag for field 1, wire type 0 = (1 << 3) | 0 = 8
    (is (= 8 (aref encoded 0)))
    (is (= 42 (aref encoded 1)))))

(test field-string-omits-empty
  "encode-field-string returns NIL for empty string."
  (is (null (sw4rm-sdk:encode-field-string 1 "")))
  (is (null (sw4rm-sdk:encode-field-string 1 nil))))

(test field-string-encodes
  "encode-field-string produces tag + length + utf8 bytes."
  (let ((encoded (sw4rm-sdk:encode-field-string 1 "hello")))
    (is (not (null encoded)))
    ;; Tag for field 1, wire type 2 = (1 << 3) | 2 = 10
    (is (= 10 (aref encoded 0)))
    ;; Length = 5
    (is (= 5 (aref encoded 1)))
    ;; "hello" in ASCII
    (is (equalp #(104 101 108 108 111) (subseq encoded 2)))))

(test field-bytes-omits-empty
  "encode-field-bytes returns NIL for empty byte arrays."
  (is (null (sw4rm-sdk:encode-field-bytes 1
              (make-array 0 :element-type '(unsigned-byte 8))))))

;;; =======================================================================
;;;  3. Envelope codec round-trip
;;; =======================================================================

(def-suite envelope-codec-suite :description "Envelope codec" :in transport-suite)
(in-suite envelope-codec-suite)

(test envelope-roundtrip-minimal
  "Encode then decode a minimal envelope preserves fields."
  (let* ((env (list :message-id "msg-001"
                    :idempotency-token ""
                    :producer-id "agent-1"
                    :correlation-id "corr-001"
                    :sequence-number 1
                    :retry-count 0
                    :message-type 2  ;; DATA
                    :content-type "application/json"
                    :content-length 0
                    :repo-id ""
                    :worktree-id ""
                    :hlc-timestamp ""
                    :ttl-ms 0
                    :payload (make-array 0 :element-type '(unsigned-byte 8))
                    :state 1  ;; SENT
                    :parent-correlation-id ""))
         (encoded (sw4rm-sdk:encode-envelope env))
         (decoded (sw4rm-sdk:decode-envelope encoded)))
    (is (string= "msg-001" (getf decoded :message-id)))
    (is (string= "agent-1" (getf decoded :producer-id)))
    (is (string= "corr-001" (getf decoded :correlation-id)))
    (is (= 1 (getf decoded :sequence-number)))
    (is (= 2 (getf decoded :message-type)))
    (is (string= "application/json" (getf decoded :content-type)))
    (is (= 1 (getf decoded :state)))))

(test envelope-roundtrip-with-payload
  "Envelope round-trip preserves binary payload."
  (let* ((payload (make-array 5 :element-type '(unsigned-byte 8)
                                :initial-contents '(1 2 3 4 5)))
         (env (list :message-id "msg-002"
                    :idempotency-token "tok-1"
                    :producer-id "agent-2"
                    :correlation-id "corr-002"
                    :sequence-number 42
                    :retry-count 3
                    :message-type 1  ;; CONTROL
                    :content-type "application/octet-stream"
                    :content-length 5
                    :repo-id "repo-1"
                    :worktree-id "wt-1"
                    :hlc-timestamp "HLC:12345:0:node"
                    :ttl-ms 5000
                    :payload payload
                    :state 2
                    :parent-correlation-id "parent-corr"))
         (encoded (sw4rm-sdk:encode-envelope env))
         (decoded (sw4rm-sdk:decode-envelope encoded)))
    (is (string= "msg-002" (getf decoded :message-id)))
    (is (string= "tok-1" (getf decoded :idempotency-token)))
    (is (= 42 (getf decoded :sequence-number)))
    (is (= 3 (getf decoded :retry-count)))
    (is (= 5000 (getf decoded :ttl-ms)))
    (is (string= "parent-corr" (getf decoded :parent-correlation-id)))
    (is (equalp payload (getf decoded :payload)))))

;;; =======================================================================
;;;  4. Router codec round-trip
;;; =======================================================================

(def-suite router-codec-suite :description "Router codec" :in transport-suite)
(in-suite router-codec-suite)

(test send-message-request-encodes
  "Encode a SendMessageRequest wrapping an envelope."
  (let* ((env (list :message-id "msg-r1"
                    :idempotency-token ""
                    :producer-id "a1"
                    :correlation-id "c1"
                    :sequence-number 1
                    :retry-count 0
                    :message-type 2
                    :content-type ""
                    :content-length 0
                    :repo-id ""
                    :worktree-id ""
                    :hlc-timestamp ""
                    :ttl-ms 0
                    :payload (make-array 0 :element-type '(unsigned-byte 8))
                    :state 0
                    :parent-correlation-id ""))
         (encoded (sw4rm-sdk::encode-send-message-request env)))
    (is (typep encoded '(simple-array (unsigned-byte 8) (*))))
    (is (> (length encoded) 0))))

(test send-message-response-decode
  "Decode a manually constructed SendMessageResponse."
  ;; Construct: field 1 (bool=true) = varint 1, field 2 (string) = "ok"
  (let* ((parts (concatenate '(simple-array (unsigned-byte 8) (*))
                             (sw4rm-sdk:encode-field-varint 1 1)
                             (sw4rm-sdk:encode-field-string 2 "ok")))
         (decoded (sw4rm-sdk::decode-send-message-response parts)))
    (is (eq t (getf decoded :accepted)))
    (is (string= "ok" (getf decoded :reason)))))

(test stream-item-roundtrip
  "Encode stream request and decode a stream item."
  (let ((req (sw4rm-sdk::encode-stream-request "agent-test")))
    (is (> (length req) 0)))
  ;; Construct a StreamItem with embedded envelope
  (let* ((env (list :message-id "s-msg"
                    :idempotency-token ""
                    :producer-id "sender"
                    :correlation-id "s-corr"
                    :sequence-number 1
                    :retry-count 0
                    :message-type 2
                    :content-type ""
                    :content-length 0
                    :repo-id ""
                    :worktree-id ""
                    :hlc-timestamp ""
                    :ttl-ms 0
                    :payload (make-array 0 :element-type '(unsigned-byte 8))
                    :state 0
                    :parent-correlation-id ""))
         (item-bytes (sw4rm-sdk::encode-field-submessage 1 (sw4rm-sdk:encode-envelope env)))
         (decoded (sw4rm-sdk::decode-stream-item item-bytes)))
    (is (string= "s-msg" (getf decoded :message-id)))
    (is (string= "sender" (getf decoded :producer-id)))))

;;; =======================================================================
;;;  5. Registry codec round-trip
;;; =======================================================================

(def-suite registry-codec-suite :description "Registry codec" :in transport-suite)
(in-suite registry-codec-suite)

(test register-agent-roundtrip
  "Encode RegisterAgentRequest and decode RegisterAgentResponse."
  (let* ((desc (list :agent-id "agent-42"
                     :name "Test Agent"
                     :description "A test agent"
                     :capabilities '("python" "code-gen")
                     :communication-class 2)) ;; STANDARD
         (encoded (sw4rm-sdk::encode-register-agent-request desc)))
    (is (> (length encoded) 0)))
  ;; Decode a response
  (let* ((resp-bytes (concatenate '(simple-array (unsigned-byte 8) (*))
                                  (sw4rm-sdk:encode-field-varint 1 1)
                                  (sw4rm-sdk:encode-field-string 2 "registered")))
         (decoded (sw4rm-sdk::decode-register-agent-response resp-bytes)))
    (is (eq t (getf decoded :accepted)))
    (is (string= "registered" (getf decoded :reason)))))

(test heartbeat-roundtrip
  "Encode HeartbeatRequest with map<string,string> health metrics."
  (let* ((encoded (sw4rm-sdk::encode-heartbeat-request
                   "agent-1" 4  ;; RUNNING
                   '(("cpu" . "45") ("memory" . "2048")))))
    (is (> (length encoded) 0))
    ;; Verify we can parse it back (decode the raw fields)
    (let ((fields (sw4rm-sdk::decode-fields encoded)))
      ;; field 1 = agent_id string
      (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
      ;; field 2 = state varint
      (is (= 4 (sw4rm-sdk::field-int fields 2)))
      ;; field 3 = map entries (should have 2)
      (let ((map-entries (sw4rm-sdk::decode-map-string-string fields 3)))
        (is (= 2 (length map-entries)))
        (is (string= "cpu" (car (first map-entries))))
        (is (string= "45" (cdr (first map-entries))))
        (is (string= "memory" (car (second map-entries))))
        (is (string= "2048" (cdr (second map-entries))))))))

(test heartbeat-response-decode
  "Decode HeartbeatResponse."
  (let* ((resp-bytes (sw4rm-sdk:encode-field-varint 1 1))
         (decoded (sw4rm-sdk::decode-heartbeat-response resp-bytes)))
    (is (eq t (getf decoded :ok)))))

(test deregister-roundtrip
  "Encode DeregisterAgentRequest and decode response."
  (let ((encoded (sw4rm-sdk::encode-deregister-agent-request "agent-1" "shutdown")))
    (is (> (length encoded) 0))
    (let ((fields (sw4rm-sdk::decode-fields encoded)))
      (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
      (is (string= "shutdown" (sw4rm-sdk::field-string fields 2)))))
  (let* ((resp-bytes (sw4rm-sdk:encode-field-varint 1 1))
         (decoded (sw4rm-sdk::decode-deregister-agent-response resp-bytes)))
    (is (eq t (getf decoded :ok)))))

;;; =======================================================================
;;;  6. gRPC availability flag
;;; =======================================================================

(def-suite grpc-avail-suite :description "gRPC availability" :in transport-suite)
(in-suite grpc-avail-suite)

(test grpc-available-is-boolean
  "The *grpc-available* flag is either T or NIL."
  (is (typep sw4rm-sdk:*grpc-available* 'boolean)))

(test grpc-status-mapping
  "signal-grpc-status signals correct condition types."
  ;; OK should not signal
  (finishes (sw4rm-sdk::signal-grpc-status 0 "/test"))
  ;; DEADLINE_EXCEEDED → rpc-timeout
  (signals sw4rm-sdk::rpc-timeout
    (sw4rm-sdk::signal-grpc-status 4 "/test"))
  ;; UNAVAILABLE → rpc-unavailable
  (signals sw4rm-sdk::rpc-unavailable
    (sw4rm-sdk::signal-grpc-status 14 "/test"))
  ;; UNIMPLEMENTED → rpc-error
  (signals sw4rm-sdk:rpc-error
    (sw4rm-sdk::signal-grpc-status 12 "/test")))

;;; =======================================================================
;;;  7. Scheduler codec round-trip
;;; =======================================================================

(def-suite scheduler-codec-suite :description "Scheduler codec" :in transport-suite)
(in-suite scheduler-codec-suite)

(test submit-task-roundtrip
  "Encode SubmitTaskRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-submit-task-request
                   "agent-1" "task-42"
                   :priority 5 :scope "file:/tmp"
                   :content-type "application/json"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "task-42" (sw4rm-sdk::field-string fields 2)))
    (is (= 5 (sw4rm-sdk::field-int fields 3)))
    (is (string= "application/json" (sw4rm-sdk::field-string fields 5)))
    (is (string= "file:/tmp" (sw4rm-sdk::field-string fields 6)))))

(test submit-task-response-decode
  "Decode SubmitTaskResponse."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-varint 1 1)
                            (sw4rm-sdk:encode-field-string 2 "queued")))
         (decoded (sw4rm-sdk::decode-submit-task-response resp)))
    (is (eq t (getf decoded :accepted)))
    (is (string= "queued" (getf decoded :reason)))))

(test preempt-request-roundtrip
  "Encode PreemptRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-preempt-request "agent-1" "task-1" "priority"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "task-1" (sw4rm-sdk::field-string fields 2)))
    (is (string= "priority" (sw4rm-sdk::field-string fields 3)))))

(test preempt-response-decode
  "Decode PreemptResponse."
  (let* ((resp (sw4rm-sdk:encode-field-varint 1 1))
         (decoded (sw4rm-sdk::decode-preempt-response resp)))
    (is (eq t (getf decoded :enqueued)))))

(test purge-activity-roundtrip
  "Encode PurgeActivityRequest with repeated task_ids."
  (let* ((encoded (sw4rm-sdk::encode-purge-activity-request "agent-1" '("t1" "t2" "t3")))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
    (is (= 3 (length (sw4rm-sdk::field-repeated-strings fields 2))))))

(test poll-activity-buffer-response-decode
  "Decode PollActivityBufferResponse with repeated ActivityEntry."
  (let* ((entry1 (concatenate '(simple-array (unsigned-byte 8) (*))
                              (sw4rm-sdk:encode-field-string 1 "task-1")
                              (sw4rm-sdk:encode-field-string 2 "repo-1")
                              (sw4rm-sdk:encode-field-string 4 "main")))
         (entry2 (concatenate '(simple-array (unsigned-byte 8) (*))
                              (sw4rm-sdk:encode-field-string 1 "task-2")
                              (sw4rm-sdk:encode-field-string 2 "repo-2")))
         (resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk::encode-field-submessage 1 entry1)
                            (sw4rm-sdk::encode-field-submessage 1 entry2)))
         (decoded (sw4rm-sdk::decode-poll-activity-buffer-response resp)))
    (is (= 2 (length decoded)))
    (is (string= "task-1" (getf (first decoded) :task-id)))
    (is (string= "main" (getf (first decoded) :branch)))
    (is (string= "task-2" (getf (second decoded) :task-id)))))

;;; =======================================================================
;;;  8. Tool codec round-trip
;;; =======================================================================

(def-suite tool-codec-suite :description "Tool codec" :in transport-suite)
(in-suite tool-codec-suite)

(test tool-call-roundtrip
  "Encode ToolCall and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-tool-call
                   (list :call-id "call-1"
                         :tool-name "read-file"
                         :provider-id "filesystem"
                         :content-type "application/json"
                         :args (babel:string-to-octets "{}" :encoding :utf-8))))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "call-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "read-file" (sw4rm-sdk::field-string fields 2)))
    (is (string= "filesystem" (sw4rm-sdk::field-string fields 3)))))

(test tool-frame-decode
  "Decode a ToolFrame."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "call-1")
                            (sw4rm-sdk:encode-field-varint 2 3)
                            (sw4rm-sdk:encode-field-varint 3 1)))
         (decoded (sw4rm-sdk::decode-tool-frame resp)))
    (is (string= "call-1" (getf decoded :call-id)))
    (is (= 3 (getf decoded :frame-no)))
    (is (eq t (getf decoded :final)))))

(test tool-error-decode
  "Decode a ToolError."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "call-1")
                            (sw4rm-sdk:encode-field-string 2 "TIMEOUT")
                            (sw4rm-sdk:encode-field-string 3 "timed out")))
         (decoded (sw4rm-sdk::decode-tool-error resp)))
    (is (string= "call-1" (getf decoded :call-id)))
    (is (string= "TIMEOUT" (getf decoded :error-code)))
    (is (string= "timed out" (getf decoded :message)))))

;;; =======================================================================
;;;  9. HITL codec round-trip
;;; =======================================================================

(def-suite hitl-codec-suite :description "HITL codec" :in transport-suite)
(in-suite hitl-codec-suite)

(test hitl-invocation-roundtrip
  "Encode HitlInvocation and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-hitl-invocation
                   (list :reason-type 2
                         :context "high risk operation"
                         :proposed-actions '("proceed" "cancel")
                         :priority 5)))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (= 2 (sw4rm-sdk::field-int fields 1)))
    (is (= 2 (length (sw4rm-sdk::field-repeated-strings fields 3))))
    (is (= 5 (sw4rm-sdk::field-int fields 4)))))

(test hitl-decision-decode
  "Decode HitlDecision."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "proceed")
                            (sw4rm-sdk:encode-field-string 3 "approved by admin")))
         (decoded (sw4rm-sdk::decode-hitl-decision resp)))
    (is (string= "proceed" (getf decoded :action)))
    (is (string= "approved by admin" (getf decoded :rationale)))))

;;; =======================================================================
;;;  10. Logging codec round-trip
;;; =======================================================================

(def-suite logging-codec-suite :description "Logging codec" :in transport-suite)
(in-suite logging-codec-suite)

(test log-event-roundtrip
  "Encode LogEvent and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-log-event
                   (list :correlation-id "corr-1"
                         :agent-id "agent-1"
                         :event-type "task.complete"
                         :level "INFO"
                         :details-json "{\"ok\":true}")))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "corr-1" (sw4rm-sdk::field-string fields 2)))
    (is (string= "agent-1" (sw4rm-sdk::field-string fields 3)))
    (is (string= "task.complete" (sw4rm-sdk::field-string fields 4)))))

(test ingest-response-decode
  "Decode IngestResponse."
  (let* ((resp (sw4rm-sdk:encode-field-varint 1 1))
         (decoded (sw4rm-sdk::decode-ingest-response resp)))
    (is (eq t (getf decoded :ok)))))

;;; =======================================================================
;;;  11. Connector codec round-trip
;;; =======================================================================

(def-suite connector-codec-suite :description "Connector codec" :in transport-suite)
(in-suite connector-codec-suite)

(test tool-descriptor-roundtrip
  "Encode and decode a ToolDescriptor."
  (let* ((desc (list :tool-name "read-file"
                     :input-schema "schema://input"
                     :output-schema "schema://output"
                     :idempotent t
                     :needs-worktree t
                     :default-timeout-s 30
                     :max-concurrency 5
                     :side-effects "filesystem"))
         (encoded (sw4rm-sdk::encode-tool-descriptor desc))
         (decoded (sw4rm-sdk::decode-tool-descriptor encoded)))
    (is (string= "read-file" (getf decoded :tool-name)))
    (is (string= "schema://input" (getf decoded :input-schema)))
    (is (eq t (getf decoded :idempotent)))
    (is (eq t (getf decoded :needs-worktree)))
    (is (= 30 (getf decoded :default-timeout-s)))
    (is (= 5 (getf decoded :max-concurrency)))))

(test provider-register-roundtrip
  "Encode ProviderRegisterRequest with tools."
  (let* ((tools (list (list :tool-name "read-file" :idempotent t)
                      (list :tool-name "write-file" :idempotent nil)))
         (encoded (sw4rm-sdk::encode-provider-register-request "fs-provider" tools))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "fs-provider" (sw4rm-sdk::field-string fields 1)))
    ;; Should have 2 submessage entries at field 2
    (is (= 2 (count 2 fields :key #'car)))))

;;; =======================================================================
;;;  12. Worktree codec round-trip
;;; =======================================================================

(def-suite worktree-codec-suite :description "Worktree codec" :in transport-suite)
(in-suite worktree-codec-suite)

(test bind-request-roundtrip
  "Encode BindRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-bind-request "agent-1" "repo-main" "wt-dev"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "repo-main" (sw4rm-sdk::field-string fields 2)))
    (is (string= "wt-dev" (sw4rm-sdk::field-string fields 3)))))

(test worktree-status-response-decode
  "Decode StatusResponse."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "repo-1")
                            (sw4rm-sdk:encode-field-string 2 "wt-1")
                            (sw4rm-sdk:encode-field-string 3 "BOUND_HOME")))
         (decoded (sw4rm-sdk::decode-worktree-status-response resp)))
    (is (string= "repo-1" (getf decoded :repo-id)))
    (is (string= "wt-1" (getf decoded :worktree-id)))
    (is (string= "BOUND_HOME" (getf decoded :state)))))

;;; =======================================================================
;;;  13. Activity codec round-trip
;;; =======================================================================

(def-suite activity-codec-suite :description "Activity codec" :in transport-suite)
(in-suite activity-codec-suite)

(test artifact-roundtrip
  "Encode and decode an Artifact."
  (let* ((content (babel:string-to-octets "(defun foo () 42)" :encoding :utf-8))
         (artifact (list :negotiation-id "neg-1"
                         :kind "code"
                         :version "v1"
                         :content-type "text/x-common-lisp"
                         :content content
                         :created-at "2026-02-21T10:00:00Z"))
         (encoded (sw4rm-sdk::encode-artifact artifact))
         (decoded (sw4rm-sdk::decode-artifact encoded)))
    (is (string= "neg-1" (getf decoded :negotiation-id)))
    (is (string= "code" (getf decoded :kind)))
    (is (string= "v1" (getf decoded :version)))
    (is (equalp content (getf decoded :content)))))

(test list-artifacts-response-decode
  "Decode ListArtifactsResponse with repeated Artifacts."
  (let* ((art1 (sw4rm-sdk::encode-artifact
                (list :negotiation-id "neg-1" :kind "code" :version "v1")))
         (art2 (sw4rm-sdk::encode-artifact
                (list :negotiation-id "neg-1" :kind "doc" :version "v2")))
         (resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk::encode-field-submessage 1 art1)
                            (sw4rm-sdk::encode-field-submessage 1 art2)))
         (decoded (sw4rm-sdk::decode-list-artifacts-response resp)))
    (is (= 2 (length decoded)))
    (is (string= "code" (getf (first decoded) :kind)))
    (is (string= "doc" (getf (second decoded) :kind)))))

;;; =======================================================================
;;;  14. Negotiation codec round-trip
;;; =======================================================================

(def-suite negotiation-codec-suite :description "Negotiation codec" :in transport-suite)
(in-suite negotiation-codec-suite)

(test negotiation-open-roundtrip
  "Encode NegotiationOpen and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-negotiation-open
                   (list :negotiation-id "neg-1"
                         :correlation-id "corr-1"
                         :topic "API design"
                         :participants '("a1" "a2" "a3")
                         :intensity 2)))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "API design" (sw4rm-sdk::field-string fields 3)))
    (is (= 3 (length (sw4rm-sdk::field-repeated-strings fields 4))))
    (is (= 2 (sw4rm-sdk::field-int fields 5)))))

(test proposal-roundtrip
  "Encode Proposal and decode fields."
  (let* ((payload (babel:string-to-octets "{\"design\":\"REST\"}" :encoding :utf-8))
         (encoded (sw4rm-sdk::encode-proposal
                   (list :negotiation-id "neg-1"
                         :from-agent "architect"
                         :content-type "application/json"
                         :payload payload)))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "architect" (sw4rm-sdk::field-string fields 2)))
    (is (equalp payload (sw4rm-sdk::field-bytes fields 4)))))

(test decision-roundtrip
  "Encode Decision and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-decision
                   (list :negotiation-id "neg-1"
                         :decided-by "consensus"
                         :content-type "application/json"
                         :result (babel:string-to-octets "{\"approved\":true}"
                                                         :encoding :utf-8))))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "consensus" (sw4rm-sdk::field-string fields 2)))))

(test abort-request-roundtrip
  "Encode AbortRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-abort-request "neg-1" "requirements changed"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "requirements changed" (sw4rm-sdk::field-string fields 2)))))

;;; =======================================================================
;;;  15. Reasoning codec round-trip
;;; =======================================================================

(def-suite reasoning-codec-suite :description "Reasoning codec" :in transport-suite)
(in-suite reasoning-codec-suite)

(test parallelism-check-roundtrip
  "Encode ParallelismCheckRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-parallelism-check-request
                   "file:src/a.lisp" "file:src/b.lisp"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "file:src/a.lisp" (sw4rm-sdk::field-string fields 1)))
    (is (string= "file:src/b.lisp" (sw4rm-sdk::field-string fields 2)))))

(test debate-evaluate-roundtrip
  "Encode DebateEvaluateRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-debate-evaluate-request
                   "neg-1" "REST" "GraphQL" "medium"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "REST" (sw4rm-sdk::field-string fields 2)))
    (is (string= "GraphQL" (sw4rm-sdk::field-string fields 3)))
    (is (string= "medium" (sw4rm-sdk::field-string fields 4)))))

(test summarize-request-roundtrip
  "Encode SummarizeRequest with segments."
  (let* ((segments (list (list :kind "user" :content "hello" :seq 1 :at "t0")
                         (list :kind "assistant" :content "hi" :seq 2 :at "t1")))
         (encoded (sw4rm-sdk::encode-summarize-request
                   "sess-1" segments :max-tokens 128 :mode "full"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "sess-1" (sw4rm-sdk::field-string fields 1)))
    ;; Should have 2 submessage entries at field 2
    (is (= 2 (count 2 fields :key #'car)))
    (is (= 128 (sw4rm-sdk::field-int fields 3)))
    (is (string= "full" (sw4rm-sdk::field-string fields 4)))))

(test summarize-response-decode
  "Decode SummarizeResponse."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "This is a summary")
                            (sw4rm-sdk:encode-field-varint 2 50)
                            (sw4rm-sdk:encode-field-string 4 "claude-3")))
         (decoded (sw4rm-sdk::decode-summarize-response resp)))
    (is (string= "This is a summary" (getf decoded :summary)))
    (is (= 50 (getf decoded :tokens)))
    (is (string= "claude-3" (getf decoded :model)))))

;;; =======================================================================
;;;  16. Workflow codec round-trip
;;; =======================================================================

(def-suite workflow-codec-suite :description "Workflow codec" :in transport-suite)
(in-suite workflow-codec-suite)

(test create-workflow-response-decode
  "Decode CreateWorkflowResponse."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-string 1 "wf-1")
                            (sw4rm-sdk:encode-field-varint 2 1)
                            (sw4rm-sdk:encode-field-string 3 "")))
         (decoded (sw4rm-sdk::decode-create-workflow-response resp)))
    (is (string= "wf-1" (getf decoded :workflow-id)))
    (is (eq t (getf decoded :success)))))

(test start-workflow-request-roundtrip
  "Encode StartWorkflowRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-start-workflow-request
                   "wf-1"
                   :workflow-data "{\"init\":true}"
                   :metadata '(("source" . "test"))))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "wf-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "{\"init\":true}" (sw4rm-sdk::field-string fields 2)))))

(test resume-workflow-request-roundtrip
  "Encode ResumeWorkflowRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-resume-workflow-request
                   "wf-1" "node-analyze"
                   :workflow-data "{\"result\":\"ok\"}"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "wf-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "node-analyze" (sw4rm-sdk::field-string fields 2)))
    (is (string= "{\"result\":\"ok\"}" (sw4rm-sdk::field-string fields 3)))))

;;; =======================================================================
;;;  17. Scheduler Policy codec round-trip
;;; =======================================================================

(def-suite scheduler-policy-codec-suite :description "Scheduler Policy codec" :in transport-suite)
(in-suite scheduler-policy-codec-suite)

(test get-effective-policy-request-roundtrip
  "Encode GetEffectivePolicyRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-get-effective-policy-request "neg-1"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))))

(test hitl-action-request-roundtrip
  "Encode HitlActionRequest and decode fields."
  (let* ((encoded (sw4rm-sdk::encode-hitl-action-request
                   "neg-1" "approve" "looks good"))
         (fields (sw4rm-sdk::decode-fields encoded)))
    (is (string= "neg-1" (sw4rm-sdk::field-string fields 1)))
    (is (string= "approve" (sw4rm-sdk::field-string fields 2)))
    (is (string= "looks good" (sw4rm-sdk::field-string fields 3)))))

(test submit-evaluation-response-decode
  "Decode SubmitEvaluationResponse."
  (let* ((resp (concatenate '(simple-array (unsigned-byte 8) (*))
                            (sw4rm-sdk:encode-field-varint 1 1)
                            (sw4rm-sdk:encode-field-string 2 "accepted")))
         (decoded (sw4rm-sdk::decode-submit-evaluation-response resp)))
    (is (eq t (getf decoded :accepted)))
    (is (string= "accepted" (getf decoded :reason)))))

;;; =======================================================================
;;;  18. Empty response decoder
;;; =======================================================================

(test empty-response-decode
  "decode-empty-response returns T."
  (is (eq t (sw4rm-sdk::decode-empty-response
             (make-array 0 :element-type '(unsigned-byte 8)))))
  (is (eq t (sw4rm-sdk::decode-empty-response
             (make-array 3 :element-type '(unsigned-byte 8)
                           :initial-element 0)))))
