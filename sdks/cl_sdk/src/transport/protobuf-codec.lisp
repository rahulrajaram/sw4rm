;;;; protobuf-codec.lisp — Plist ↔ protobuf wire format (manual encoding)
;;;;
;;;; Implements the subset of proto3 wire format needed for SW4RM messages.
;;;; No protoc compilation step required.  Can be swapped for cl-protobufs
;;;; later without API changes.
;;;;
;;;; Wire format reference: https://protobuf.dev/programming-guides/encoding/

(in-package #:sw4rm-sdk)

;;; -----------------------------------------------------------------------
;;;  Primitive wire-format helpers
;;; -----------------------------------------------------------------------

(defun encode-varint (value)
  "Encode a non-negative integer as a protobuf varint.  Returns an octet vector."
  (declare (type (integer 0) value))
  (let ((result (make-array 0 :element-type '(unsigned-byte 8)
                              :adjustable t :fill-pointer 0)))
    (loop
      (let ((byte (logand value #x7f)))
        (setf value (ash value -7))
        (if (zerop value)
            (progn (vector-push-extend byte result)
                   (return))
            (vector-push-extend (logior byte #x80) result))))
    (coerce result '(simple-array (unsigned-byte 8) (*)))))

(defun decode-varint (buffer offset)
  "Decode a varint from BUFFER starting at OFFSET.
Returns (values decoded-integer new-offset)."
  (declare (type (simple-array (unsigned-byte 8) (*)) buffer)
           (type fixnum offset))
  (let ((result 0)
        (shift 0))
    (loop for pos from offset below (length buffer)
          for byte = (aref buffer pos)
          do (setf result (logior result (ash (logand byte #x7f) shift)))
             (incf shift 7)
             (when (zerop (logand byte #x80))
               (return-from decode-varint (values result (1+ pos)))))
    (error "Truncated varint at offset ~D" offset)))

(defun encode-tag (field-number wire-type)
  "Encode a protobuf field tag as a varint.
WIRE-TYPE: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit."
  (encode-varint (logior (ash field-number 3) wire-type)))

;;; -----------------------------------------------------------------------
;;;  Field encoders
;;; -----------------------------------------------------------------------

(defun encode-field-varint (field-number value)
  "Encode a varint field (int32/int64/uint32/uint64/enum/bool).
Omits the field entirely when VALUE is 0 (proto3 default)."
  (when (and value (not (zerop value)))
    (concatenate '(simple-array (unsigned-byte 8) (*))
                 (encode-tag field-number 0)
                 (encode-varint value))))

(defun encode-field-string (field-number value)
  "Encode a string field.  Omits when VALUE is NIL or empty."
  (when (and value (plusp (length value)))
    (let ((bytes (babel:string-to-octets value :encoding :utf-8)))
      (concatenate '(simple-array (unsigned-byte 8) (*))
                   (encode-tag field-number 2)
                   (encode-varint (length bytes))
                   bytes))))

(defun encode-field-bytes (field-number value)
  "Encode a bytes field.  VALUE is an octet vector.  Omits when empty/nil."
  (when (and value (plusp (length value)))
    (concatenate '(simple-array (unsigned-byte 8) (*))
                 (encode-tag field-number 2)
                 (encode-varint (length value))
                 value)))

(defun encode-field-submessage (field-number encoded-bytes)
  "Encode a submessage field.  ENCODED-BYTES is the already-encoded submessage.
Omits when nil or empty."
  (when (and encoded-bytes (plusp (length encoded-bytes)))
    (concatenate '(simple-array (unsigned-byte 8) (*))
                 (encode-tag field-number 2)
                 (encode-varint (length encoded-bytes))
                 encoded-bytes)))

(defun encode-field-bool (field-number value)
  "Encode a boolean field.  Omits when VALUE is NIL (proto3 false default)."
  (when value
    (encode-field-varint field-number 1)))

;;; -----------------------------------------------------------------------
;;;  Field decoders (generic wire-format parser)
;;; -----------------------------------------------------------------------

(defun decode-fields (buffer &optional (start 0) (end nil))
  "Parse protobuf wire format from BUFFER[START..END].
Returns an alist of (field-number . raw-value) where raw-value is:
  - integer for varint fields (wire type 0)
  - octet vector for length-delimited fields (wire type 2)
  - ignored for wire types 1 and 5 (64-bit, 32-bit fixed)."
  (let ((end (or end (length buffer)))
        (fields nil)
        (pos start))
    (loop while (< pos end) do
      (multiple-value-bind (tag new-pos) (decode-varint buffer pos)
        (setf pos new-pos)
        (let ((field-number (ash tag -3))
              (wire-type (logand tag 7)))
          (ecase wire-type
            (0 ; varint
             (multiple-value-bind (val np) (decode-varint buffer pos)
               (push (cons field-number val) fields)
               (setf pos np)))
            (1 ; 64-bit fixed — skip 8 bytes
             (push (cons field-number
                         (subseq buffer pos (min (+ pos 8) end)))
                   fields)
             (incf pos 8))
            (2 ; length-delimited
             (multiple-value-bind (len np) (decode-varint buffer pos)
               (setf pos np)
               (push (cons field-number
                           (subseq buffer pos (min (+ pos len) end)))
                     fields)
               (incf pos len)))
            (5 ; 32-bit fixed — skip 4 bytes
             (push (cons field-number
                         (subseq buffer pos (min (+ pos 4) end)))
                   fields)
             (incf pos 4))))))
    (nreverse fields)))

(defun field-value (fields field-number &optional default)
  "Retrieve value for FIELD-NUMBER from decoded fields alist."
  (let ((pair (assoc field-number fields)))
    (if pair (cdr pair) default)))

(defun field-string (fields field-number)
  "Retrieve a string field from decoded fields."
  (let ((raw (field-value fields field-number)))
    (if (and raw (typep raw '(simple-array (unsigned-byte 8) (*))))
        (babel:octets-to-string raw :encoding :utf-8)
        (or raw ""))))

(defun field-bytes (fields field-number)
  "Retrieve a bytes field from decoded fields."
  (let ((raw (field-value fields field-number)))
    (if (and raw (typep raw '(simple-array (unsigned-byte 8) (*))))
        raw
        (make-array 0 :element-type '(unsigned-byte 8)))))

(defun field-int (fields field-number &optional (default 0))
  "Retrieve an integer/enum/bool field from decoded fields."
  (let ((raw (field-value fields field-number)))
    (if (integerp raw) raw default)))

(defun field-repeated-strings (fields field-number)
  "Collect all string values for a repeated string field."
  (loop for (fn . val) in fields
        when (= fn field-number)
        collect (if (typep val '(simple-array (unsigned-byte 8) (*)))
                    (babel:octets-to-string val :encoding :utf-8)
                    "")))

;;; -----------------------------------------------------------------------
;;;  Map<string,string> encoding (for HeartbeatRequest.health)
;;; -----------------------------------------------------------------------
;;;  Proto3 map<string,string> is encoded as repeated submessages where
;;;  each entry has field 1 = key (string) and field 2 = value (string).

(defun encode-map-string-string (field-number alist)
  "Encode an alist of (key . value) string pairs as a proto3 map<string,string>.
Each entry is a submessage at FIELD-NUMBER with field 1=key, field 2=value."
  (when alist
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (loop for (key . val) in alist
                 for entry = (concatenate '(simple-array (unsigned-byte 8) (*))
                                          (encode-field-string 1 (princ-to-string key))
                                          (encode-field-string 2 (princ-to-string val)))
                 collect (encode-field-submessage field-number entry)))))

(defun decode-map-string-string (fields field-number)
  "Decode repeated submessage entries at FIELD-NUMBER as an alist of string pairs."
  (loop for (fn . val) in fields
        when (and (= fn field-number)
                  (typep val '(simple-array (unsigned-byte 8) (*))))
        collect (let ((sub (decode-fields val)))
                  (cons (field-string sub 1)
                        (field-string sub 2)))))

;;; -----------------------------------------------------------------------
;;;  Envelope codec  (common.proto: Envelope, 17 fields incl. field 100)
;;; -----------------------------------------------------------------------

(defun encode-envelope (envelope)
  "Encode an envelope plist to protobuf wire bytes.
ENVELOPE is a plist as returned by make-envelope."
  (let ((parts (list
                (encode-field-string  1  (getf envelope :message-id))
                (encode-field-string  2  (getf envelope :idempotency-token))
                (encode-field-string  3  (getf envelope :producer-id))
                (encode-field-string  4  (getf envelope :correlation-id))
                (encode-field-varint  5  (getf envelope :sequence-number))
                (encode-field-varint  6  (getf envelope :retry-count))
                (encode-field-varint  7  (getf envelope :message-type))
                (encode-field-string  8  (getf envelope :content-type))
                (encode-field-varint  9  (getf envelope :content-length))
                (encode-field-string  10 (getf envelope :repo-id))
                (encode-field-string  11 (getf envelope :worktree-id))
                (encode-field-string  12 (getf envelope :hlc-timestamp))
                (encode-field-varint  13 (getf envelope :ttl-ms))
                ;; field 14 = google.protobuf.Timestamp — skip for now
                (encode-field-bytes   15 (getf envelope :payload))
                (encode-field-varint  16 (getf envelope :state))
                ;; SW4-004 extension field
                (encode-field-string  100 (getf envelope :parent-correlation-id)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-envelope (buffer)
  "Decode protobuf wire bytes into an envelope plist."
  (let ((f (decode-fields buffer)))
    (list :message-id          (field-string f 1)
          :idempotency-token   (field-string f 2)
          :producer-id         (field-string f 3)
          :correlation-id      (field-string f 4)
          :sequence-number     (field-int f 5 1)
          :retry-count         (field-int f 6 0)
          :message-type        (field-int f 7 0)
          :content-type        (field-string f 8)
          :content-length      (field-int f 9 0)
          :repo-id             (field-string f 10)
          :worktree-id         (field-string f 11)
          :hlc-timestamp       (field-string f 12)
          :ttl-ms              (field-int f 13 0)
          :payload             (field-bytes f 15)
          :state               (field-int f 16 0)
          :parent-correlation-id (field-string f 100))))

;;; -----------------------------------------------------------------------
;;;  Router codecs  (router.proto)
;;; -----------------------------------------------------------------------

(defun encode-send-message-request (envelope)
  "Encode a SendMessageRequest: field 1 = Envelope submessage."
  (encode-field-submessage 1 (encode-envelope envelope)))

(defun decode-send-message-response (buffer)
  "Decode a SendMessageResponse: field 1 = accepted (bool), field 2 = reason (string)."
  (let ((f (decode-fields buffer)))
    (list :accepted (not (zerop (field-int f 1 0)))
          :reason   (field-string f 2))))

(defun encode-stream-request (agent-id)
  "Encode a StreamRequest: field 1 = agent_id (string)."
  (encode-field-string 1 agent-id))

(defun decode-stream-item (buffer)
  "Decode a StreamItem: field 1 = Envelope submessage."
  (let ((f (decode-fields buffer)))
    (let ((envelope-bytes (field-bytes f 1)))
      (if (plusp (length envelope-bytes))
          (decode-envelope envelope-bytes)
          nil))))

;;; -----------------------------------------------------------------------
;;;  Registry codecs  (registry.proto)
;;; -----------------------------------------------------------------------

(defun encode-agent-descriptor (desc)
  "Encode an AgentDescriptor plist to protobuf bytes.
DESC is a plist with :agent-id, :name, :description, :capabilities, etc."
  (let ((parts (list
                (encode-field-string 1 (getf desc :agent-id))
                (encode-field-string 2 (getf desc :name))
                (encode-field-string 3 (getf desc :description))
                ;; field 4 = repeated string capabilities
                (when (getf desc :capabilities)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (cap) (encode-field-string 4 cap))
                                 (getf desc :capabilities))))
                ;; field 5 = CommunicationClass enum
                (encode-field-varint 5 (getf desc :communication-class))
                ;; field 6 = repeated string modalities_supported
                (when (getf desc :modalities-supported)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (m) (encode-field-string 6 m))
                                 (getf desc :modalities-supported))))
                ;; field 7 = repeated string reasoning_connectors
                (when (getf desc :reasoning-connectors)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (r) (encode-field-string 7 r))
                                 (getf desc :reasoning-connectors))))
                ;; field 8 = bytes public_key
                (encode-field-bytes 8 (getf desc :public-key))
                ;; SW4-004 extension fields
                (encode-field-varint 100 (getf desc :registration-type))
                (encode-field-varint 101 (getf desc :max-concurrent-delegations)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-register-agent-request (agent-descriptor)
  "Encode a RegisterAgentRequest: field 1 = AgentDescriptor submessage."
  (encode-field-submessage 1 (encode-agent-descriptor agent-descriptor)))

(defun decode-register-agent-response (buffer)
  "Decode a RegisterAgentResponse: field 1 = accepted (bool), field 2 = reason (string)."
  (let ((f (decode-fields buffer)))
    (list :accepted (not (zerop (field-int f 1 0)))
          :reason   (field-string f 2))))

(defun encode-heartbeat-request (agent-id state &optional health-alist)
  "Encode a HeartbeatRequest.
AGENT-ID: string, STATE: AgentState enum integer, HEALTH-ALIST: ((key . val) ...)."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-varint 2 state)
                (encode-map-string-string 3 health-alist))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-heartbeat-response (buffer)
  "Decode a HeartbeatResponse: field 1 = ok (bool)."
  (let ((f (decode-fields buffer)))
    (list :ok (not (zerop (field-int f 1 0))))))

(defun encode-deregister-agent-request (agent-id &optional reason)
  "Encode a DeregisterAgentRequest: field 1 = agent_id, field 2 = reason."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 reason))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-deregister-agent-response (buffer)
  "Decode a DeregisterAgentResponse: field 1 = ok (bool)."
  (let ((f (decode-fields buffer)))
    (list :ok (not (zerop (field-int f 1 0))))))

;;; -----------------------------------------------------------------------
;;;  Common: Empty response decoder
;;; -----------------------------------------------------------------------

(defun decode-empty-response (buffer)
  "Decode an empty protobuf response (sw4rm.common.Empty).
Returns T unconditionally — the call succeeded if we got here."
  (declare (ignore buffer))
  t)

;;; -----------------------------------------------------------------------
;;;  Scheduler codecs  (scheduler.proto)
;;; -----------------------------------------------------------------------

(defun encode-submit-task-request (agent-id task-id &key (priority 0) (params #()) (content-type "") (scope ""))
  "Encode a SubmitTaskRequest."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 task-id)
                (encode-field-varint 3 (if (minusp priority)
                                           ;; proto3 int32 uses two's complement for negatives
                                           (+ (ash 1 32) priority)
                                           priority))
                (encode-field-bytes  4 params)
                (encode-field-string 5 content-type)
                (encode-field-string 6 scope))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-submit-task-response (buffer)
  "Decode a SubmitTaskResponse: field 1 = accepted (bool), field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :accepted (not (zerop (field-int f 1 0)))
          :reason   (field-string f 2))))

(defun encode-preempt-request (agent-id task-id &optional reason)
  "Encode a PreemptRequest."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 task-id)
                (encode-field-string 3 reason))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-preempt-response (buffer)
  "Decode a PreemptResponse: field 1 = enqueued (bool)."
  (let ((f (decode-fields buffer)))
    (list :enqueued (not (zerop (field-int f 1 0))))))

(defun encode-shutdown-agent-request (agent-id)
  "Encode a ShutdownAgentRequest: field 1 = agent_id."
  (or (encode-field-string 1 agent-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-shutdown-agent-response (buffer)
  "Decode a ShutdownAgentResponse: field 1 = ok (bool)."
  (let ((f (decode-fields buffer)))
    (list :ok (not (zerop (field-int f 1 0))))))

(defun encode-poll-activity-buffer-request (agent-id)
  "Encode a PollActivityBufferRequest: field 1 = agent_id."
  (or (encode-field-string 1 agent-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-activity-entry (buffer)
  "Decode an ActivityEntry submessage."
  (let ((f (decode-fields buffer)))
    (list :task-id      (field-string f 1)
          :repo-id      (field-string f 2)
          :worktree-id  (field-string f 3)
          :branch       (field-string f 4)
          :description  (field-string f 5)
          :timestamp    (field-string f 6))))

(defun decode-poll-activity-buffer-response (buffer)
  "Decode a PollActivityBufferResponse: field 1 = repeated ActivityEntry."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1) (typep val '(simple-array (unsigned-byte 8) (*))))
          collect (decode-activity-entry val))))

(defun encode-purge-activity-request (agent-id task-ids)
  "Encode a PurgeActivityRequest: field 1 = agent_id, field 2 = repeated task_ids."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (when task-ids
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (tid) (encode-field-string 2 tid))
                                 task-ids))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-purge-activity-response (buffer)
  "Decode a PurgeActivityResponse: field 1 = purged (uint32)."
  (let ((f (decode-fields buffer)))
    (list :purged (field-int f 1 0))))

;;; -----------------------------------------------------------------------
;;;  Tool codecs  (tool.proto)
;;; -----------------------------------------------------------------------

(defun encode-tool-call (tool-call)
  "Encode a ToolCall message from a plist."
  (let ((parts (list
                (encode-field-string 1 (getf tool-call :call-id))
                (encode-field-string 2 (getf tool-call :tool-name))
                (encode-field-string 3 (getf tool-call :provider-id))
                (encode-field-string 4 (getf tool-call :content-type))
                (encode-field-bytes  5 (let ((args (getf tool-call :args)))
                                         (if (stringp args)
                                             (babel:string-to-octets args :encoding :utf-8)
                                             args)))
                ;; field 6 = ExecutionPolicy submessage — skip for now
                (encode-field-bool   7 (getf tool-call :stream)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-tool-frame (buffer)
  "Decode a ToolFrame response."
  (let ((f (decode-fields buffer)))
    (list :call-id      (field-string f 1)
          :frame-no     (field-int f 2 0)
          :final        (not (zerop (field-int f 3 0)))
          :content-type (field-string f 4)
          :data         (field-bytes f 5)
          :summary      (field-bytes f 6))))

(defun decode-tool-error (buffer)
  "Decode a ToolError response."
  (let ((f (decode-fields buffer)))
    (list :call-id    (field-string f 1)
          :error-code (field-string f 2)
          :message    (field-string f 3))))

;;; -----------------------------------------------------------------------
;;;  HITL codecs  (hitl.proto)
;;; -----------------------------------------------------------------------

(defun encode-hitl-invocation (invocation)
  "Encode a HitlInvocation message."
  (let ((parts (list
                (encode-field-varint 1 (or (getf invocation :reason-type) 0))
                (encode-field-bytes  2 (let ((ctx (getf invocation :context)))
                                         (if (stringp ctx)
                                             (babel:string-to-octets ctx :encoding :utf-8)
                                             ctx)))
                (when (getf invocation :proposed-actions)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (a) (encode-field-string 3 a))
                                 (getf invocation :proposed-actions))))
                (encode-field-varint 4 (or (getf invocation :priority) 0)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-hitl-decision (buffer)
  "Decode a HitlDecision response."
  (let ((f (decode-fields buffer)))
    (list :action           (field-string f 1)
          :decision-payload (field-bytes f 2)
          :rationale        (field-string f 3))))

;;; -----------------------------------------------------------------------
;;;  Logging codecs  (logging.proto)
;;; -----------------------------------------------------------------------

(defun encode-log-event (event)
  "Encode a LogEvent message.
EVENT plist: :correlation-id, :agent-id, :event-type, :level, :details-json.
Note: field 1 (Timestamp) is skipped; use string fields for time."
  (let ((parts (list
                ;; field 1 = google.protobuf.Timestamp — skip
                (encode-field-string 2 (getf event :correlation-id))
                (encode-field-string 3 (getf event :agent-id))
                (encode-field-string 4 (or (getf event :event-type)
                                           (princ-to-string (or (getf event :level) "INFO"))))
                (encode-field-string 5 (princ-to-string (or (getf event :level) "INFO")))
                (encode-field-string 6 (or (getf event :details-json)
                                           (getf event :message)
                                           "")))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-ingest-response (buffer)
  "Decode an IngestResponse: field 1 = ok (bool)."
  (let ((f (decode-fields buffer)))
    (list :ok (not (zerop (field-int f 1 0))))))

;;; -----------------------------------------------------------------------
;;;  Connector codecs  (connector.proto)
;;; -----------------------------------------------------------------------

(defun encode-tool-descriptor (desc)
  "Encode a ToolDescriptor submessage."
  (let ((parts (list
                (encode-field-string  1 (getf desc :tool-name))
                (encode-field-string  2 (getf desc :input-schema))
                (encode-field-string  3 (getf desc :output-schema))
                (encode-field-bool    4 (getf desc :idempotent))
                (encode-field-bool    5 (getf desc :needs-worktree))
                (encode-field-varint  6 (or (getf desc :default-timeout-s) 0))
                (encode-field-varint  7 (or (getf desc :max-concurrency) 0))
                (encode-field-string  8 (getf desc :side-effects)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-tool-descriptor (buffer)
  "Decode a ToolDescriptor submessage."
  (let ((f (decode-fields buffer)))
    (list :tool-name         (field-string f 1)
          :input-schema      (field-string f 2)
          :output-schema     (field-string f 3)
          :idempotent        (not (zerop (field-int f 4 0)))
          :needs-worktree    (not (zerop (field-int f 5 0)))
          :default-timeout-s (field-int f 6 0)
          :max-concurrency   (field-int f 7 0)
          :side-effects      (field-string f 8))))

(defun encode-provider-register-request (provider-id tools)
  "Encode a ProviderRegisterRequest."
  (let ((parts (list
                (encode-field-string 1 provider-id)
                (when tools
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (tool)
                                   (encode-field-submessage 2 (encode-tool-descriptor tool)))
                                 tools))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-provider-register-response (buffer)
  "Decode a ProviderRegisterResponse: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-describe-tools-request (provider-id)
  "Encode a DescribeToolsRequest: field 1 = provider_id."
  (or (encode-field-string 1 provider-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-describe-tools-response (buffer)
  "Decode a DescribeToolsResponse: field 1 = repeated ToolDescriptor."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1) (typep val '(simple-array (unsigned-byte 8) (*))))
          collect (decode-tool-descriptor val))))

;;; -----------------------------------------------------------------------
;;;  Worktree codecs  (worktree.proto)
;;; -----------------------------------------------------------------------

(defun encode-bind-request (agent-id repo-id worktree-id)
  "Encode a BindRequest."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 repo-id)
                (encode-field-string 3 worktree-id))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-bind-response (buffer)
  "Decode a BindResponse: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-unbind-request (agent-id)
  "Encode an UnbindRequest: field 1 = agent_id."
  (or (encode-field-string 1 agent-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-unbind-response (buffer)
  "Decode an UnbindResponse: field 1 = ok."
  (let ((f (decode-fields buffer)))
    (list :ok (not (zerop (field-int f 1 0))))))

(defun encode-switch-request (agent-id target-worktree-id &optional requires-hitl)
  "Encode a SwitchRequest."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 target-worktree-id)
                (encode-field-bool   3 requires-hitl))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-switch-approve (agent-id target-worktree-id &optional ttl-ms)
  "Encode a SwitchApprove."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 target-worktree-id)
                (encode-field-varint 3 (or ttl-ms 0)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-switch-reject (agent-id reason)
  "Encode a SwitchReject."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 reason))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-worktree-status-request (agent-id)
  "Encode a StatusRequest: field 1 = agent_id."
  (or (encode-field-string 1 agent-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-worktree-status-response (buffer)
  "Decode a StatusResponse."
  (let ((f (decode-fields buffer)))
    (list :repo-id     (field-string f 1)
          :worktree-id (field-string f 2)
          :state       (field-string f 3))))

;;; -----------------------------------------------------------------------
;;;  Activity codecs  (activity.proto)
;;; -----------------------------------------------------------------------

(defun encode-artifact (artifact)
  "Encode an Artifact submessage."
  (let ((parts (list
                (encode-field-string 1 (getf artifact :negotiation-id))
                (encode-field-string 2 (getf artifact :kind))
                (encode-field-string 3 (getf artifact :version))
                (encode-field-string 4 (getf artifact :content-type))
                (encode-field-bytes  5 (let ((c (getf artifact :content)))
                                         (if (stringp c)
                                             (babel:string-to-octets c :encoding :utf-8)
                                             c)))
                (encode-field-string 6 (getf artifact :created-at)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-artifact (buffer)
  "Decode an Artifact submessage."
  (let ((f (decode-fields buffer)))
    (list :negotiation-id (field-string f 1)
          :kind           (field-string f 2)
          :version        (field-string f 3)
          :content-type   (field-string f 4)
          :content        (field-bytes f 5)
          :created-at     (field-string f 6))))

(defun encode-append-artifact-request (artifact)
  "Encode an AppendArtifactRequest: field 1 = Artifact submessage."
  (encode-field-submessage 1 (encode-artifact artifact)))

(defun decode-append-artifact-response (buffer)
  "Decode an AppendArtifactResponse: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-list-artifacts-request (negotiation-id &optional kind)
  "Encode a ListArtifactsRequest."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-string 2 kind))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-list-artifacts-response (buffer)
  "Decode a ListArtifactsResponse: field 1 = repeated Artifact."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1) (typep val '(simple-array (unsigned-byte 8) (*))))
          collect (decode-artifact val))))

;;; -----------------------------------------------------------------------
;;;  Negotiation codecs  (negotiation.proto)
;;; -----------------------------------------------------------------------

(defun encode-negotiation-open (negotiation)
  "Encode a NegotiationOpen message."
  (let ((parts (list
                (encode-field-string 1 (getf negotiation :negotiation-id))
                (encode-field-string 2 (getf negotiation :correlation-id))
                (encode-field-string 3 (getf negotiation :topic))
                (when (getf negotiation :participants)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (p) (encode-field-string 4 p))
                                 (getf negotiation :participants))))
                (encode-field-varint 5 (or (getf negotiation :intensity) 0)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-proposal (proposal)
  "Encode a Proposal message."
  (let ((parts (list
                (encode-field-string 1 (getf proposal :negotiation-id))
                (encode-field-string 2 (getf proposal :from-agent))
                (encode-field-string 3 (getf proposal :content-type))
                (encode-field-bytes  4 (let ((p (getf proposal :payload)))
                                         (if (stringp p)
                                             (babel:string-to-octets p :encoding :utf-8)
                                             p))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-counter-proposal (counter)
  "Encode a CounterProposal message (same layout as Proposal)."
  (encode-proposal counter))

(defun encode-evaluation (evaluation)
  "Encode an Evaluation message."
  (let ((parts (list
                (encode-field-string 1 (getf evaluation :negotiation-id))
                (encode-field-string 2 (getf evaluation :from-agent))
                ;; field 3 = double confidence_score — encode as 64-bit fixed
                ;; For simplicity, skip double encoding; use field 4 notes only
                (encode-field-string 4 (getf evaluation :notes)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-decision (decision)
  "Encode a Decision message."
  (let ((parts (list
                (encode-field-string 1 (getf decision :negotiation-id))
                (encode-field-string 2 (getf decision :decided-by))
                (encode-field-string 3 (getf decision :content-type))
                (encode-field-bytes  4 (let ((r (getf decision :result)))
                                         (if (stringp r)
                                             (babel:string-to-octets r :encoding :utf-8)
                                             r))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-abort-request (negotiation-id reason)
  "Encode an AbortRequest."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-string 2 reason))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

;;; -----------------------------------------------------------------------
;;;  Reasoning codecs  (reasoning.proto)
;;; -----------------------------------------------------------------------

(defun encode-parallelism-check-request (scope-a scope-b)
  "Encode a ParallelismCheckRequest."
  (let ((parts (list
                (encode-field-string 1 scope-a)
                (encode-field-string 2 scope-b))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-parallelism-check-response (buffer)
  "Decode a ParallelismCheckResponse.
Note: field 1 = double (wire type 1, 8 bytes). We decode it as raw bytes."
  (let ((f (decode-fields buffer)))
    (list :confidence-score (field-int f 1 0)  ;; double not decoded to float yet
          :notes            (field-string f 2))))

(defun encode-debate-evaluate-request (negotiation-id proposal-a proposal-b &optional intensity)
  "Encode a DebateEvaluateRequest."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-string 2 proposal-a)
                (encode-field-string 3 proposal-b)
                (encode-field-string 4 intensity))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-debate-evaluate-response (buffer)
  "Decode a DebateEvaluateResponse."
  (let ((f (decode-fields buffer)))
    (list :confidence-score (field-int f 1 0)
          :notes            (field-string f 2))))

(defun encode-text-segment (segment)
  "Encode a TextSegment submessage."
  (let ((parts (list
                (encode-field-string 1 (getf segment :kind))
                (encode-field-string 2 (getf segment :content))
                (encode-field-varint 3 (or (getf segment :seq) 0))
                (encode-field-string 4 (getf segment :at)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun encode-summarize-request (session-id segments &key (max-tokens 0) mode)
  "Encode a SummarizeRequest."
  (let ((parts (list
                (encode-field-string 1 session-id)
                (when segments
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (seg)
                                   (encode-field-submessage 2 (encode-text-segment seg)))
                                 segments)))
                (encode-field-varint 3 max-tokens)
                (encode-field-string 4 mode))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-summarize-response (buffer)
  "Decode a SummarizeResponse."
  (let ((f (decode-fields buffer)))
    (list :summary     (field-string f 1)
          :tokens      (field-int f 2 0)
          :cost-cents  (field-int f 3 0)  ;; double not decoded to float
          :model       (field-string f 4))))

;;; -----------------------------------------------------------------------
;;;  Workflow codecs  (workflow.proto)
;;; -----------------------------------------------------------------------

(defun encode-create-workflow-request (definition)
  "Encode a CreateWorkflowRequest: field 1 = WorkflowDefinition submessage.
DEFINITION plist: :workflow-id, :metadata (alist).
Note: nodes and timestamps are complex — encode workflow-id only for now."
  (let ((def-bytes (or (encode-field-string 1 (getf definition :workflow-id))
                       (make-array 0 :element-type '(unsigned-byte 8)))))
    (encode-field-submessage 1 def-bytes)))

(defun decode-create-workflow-response (buffer)
  "Decode a CreateWorkflowResponse."
  (let ((f (decode-fields buffer)))
    (list :workflow-id (field-string f 1)
          :success     (not (zerop (field-int f 2 0)))
          :error       (field-string f 3))))

(defun encode-start-workflow-request (workflow-id &key workflow-data metadata)
  "Encode a StartWorkflowRequest."
  (let ((parts (list
                (encode-field-string 1 workflow-id)
                (encode-field-string 2 workflow-data)
                (encode-map-string-string 3 metadata))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-start-workflow-response (buffer)
  "Decode a StartWorkflowResponse."
  (let ((f (decode-fields buffer)))
    (list :workflow-id (field-string f 1)
          ;; field 2 = WorkflowState submessage — skip deep decode for now
          :success     (not (zerop (field-int f 3 0)))
          :error       (field-string f 4))))

(defun encode-get-workflow-state-request (workflow-id)
  "Encode a GetWorkflowStateRequest: field 1 = workflow_id."
  (or (encode-field-string 1 workflow-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-workflow-state-response (buffer)
  "Decode a GetWorkflowStateResponse."
  (let ((f (decode-fields buffer)))
    (list ;; field 1 = WorkflowState submessage — skip deep decode
          :success (not (zerop (field-int f 2 0)))
          :error   (field-string f 3))))

(defun encode-resume-workflow-request (workflow-id node-id &key workflow-data metadata)
  "Encode a ResumeWorkflowRequest."
  (let ((parts (list
                (encode-field-string 1 workflow-id)
                (encode-field-string 2 node-id)
                (encode-field-string 3 workflow-data)
                (encode-map-string-string 4 metadata))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-resume-workflow-response (buffer)
  "Decode a ResumeWorkflowResponse."
  (let ((f (decode-fields buffer)))
    (list :workflow-id (field-string f 1)
          :success     (not (zerop (field-int f 3 0)))
          :error       (field-string f 4))))

;;; -----------------------------------------------------------------------
;;;  Scheduler Policy codecs  (scheduler_policy.proto)
;;; -----------------------------------------------------------------------
;;;  Note: NegotiationPolicy, PolicyProfile, EffectivePolicy, EvaluationReport
;;;  are complex sub-messages from policy.proto. For now, pass-through as bytes.

(defun encode-set-negotiation-policy-request (policy-bytes)
  "Encode a SetNegotiationPolicyRequest: field 1 = NegotiationPolicy submessage.
POLICY-BYTES is already-encoded NegotiationPolicy or raw bytes."
  (encode-field-submessage 1 policy-bytes))

(defun decode-set-negotiation-policy-response (buffer)
  "Decode: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-get-negotiation-policy-request ()
  "Encode a GetNegotiationPolicyRequest (empty message)."
  (make-array 0 :element-type '(unsigned-byte 8)))

(defun decode-get-negotiation-policy-response (buffer)
  "Decode: field 1 = NegotiationPolicy submessage (raw bytes)."
  (let ((f (decode-fields buffer)))
    (list :policy-bytes (field-bytes f 1))))

(defun encode-get-effective-policy-request (negotiation-id)
  "Encode a GetEffectivePolicyRequest: field 1 = negotiation_id."
  (or (encode-field-string 1 negotiation-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-effective-policy-response (buffer)
  "Decode: field 1 = EffectivePolicy submessage (raw bytes)."
  (let ((f (decode-fields buffer)))
    (list :effective-bytes (field-bytes f 1))))

(defun encode-submit-evaluation-request (negotiation-id report-bytes)
  "Encode a SubmitEvaluationRequest."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-submessage 2 report-bytes))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-submit-evaluation-response (buffer)
  "Decode: field 1 = accepted, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :accepted (not (zerop (field-int f 1 0)))
          :reason   (field-string f 2))))

(defun encode-hitl-action-request (negotiation-id action rationale)
  "Encode a HitlActionRequest."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-string 2 action)
                (encode-field-string 3 rationale))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-hitl-action-response (buffer)
  "Decode: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))
