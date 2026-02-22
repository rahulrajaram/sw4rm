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

(defun %double-float-to-u64 (value)
  "Convert VALUE to an IEEE-754 64-bit integer representation."
  #+sbcl
  (sb-kernel:double-float-bits (coerce value 'double-float))
  #-sbcl
  (error "Double encoding requires SBCL (value: ~S)" value))

(defun %u64-to-double-float (bits)
  "Convert IEEE-754 64-bit integer BITS to a double-float."
  #+sbcl
  (let* ((hi-unsigned (ldb (byte 32 32) bits))
         (hi-signed (if (> hi-unsigned #x7fffffff)
                        (- hi-unsigned #x100000000)
                        hi-unsigned))
         (lo-unsigned (ldb (byte 32 0) bits)))
    (sb-kernel:make-double-float hi-signed lo-unsigned))
  #-sbcl
  (error "Double decoding requires SBCL (bits: ~S)" bits))

(defun %single-float-to-u32 (value)
  "Convert VALUE to an IEEE-754 32-bit integer representation."
  #+sbcl
  (ldb (byte 32 0) (sb-kernel:single-float-bits (coerce value 'single-float)))
  #-sbcl
  (error "Float encoding requires SBCL (value: ~S)" value))

(defun %u32-to-single-float (bits)
  "Convert IEEE-754 32-bit integer bits to a single-float."
  #+sbcl
  (sb-kernel:make-single-float (ldb (byte 32 0) bits))
  #-sbcl
  (error "Float decoding requires SBCL (bits: ~S)" bits))

(defun %bytes-from-text-or-bytes (value)
  "Normalize string or byte-vector values for timestamp-like wire fields."
  (cond
    ((and value (typep value '(simple-array (unsigned-byte 8) (*))))
     value)
    ((and value (stringp value))
     (babel:string-to-octets value :encoding :utf-8))
    (t nil)))

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

(defun encode-field-double (field-number value)
  "Encode a double field (wire type 1, fixed 64-bit little-endian).
Omits when VALUE is NIL or numerically zero (proto3 default)."
  (when (and value (or (not (numberp value)) (not (zerop value))))
    (let* ((bits (%double-float-to-u64 value))
           (bytes (make-array 8 :element-type '(unsigned-byte 8))))
      (dotimes (i 8)
        (setf (aref bytes i) (ldb (byte 8 (* i 8)) bits)))
      (concatenate '(simple-array (unsigned-byte 8) (*))
                   (encode-tag field-number 1)
                   bytes))))

(defun encode-field-float (field-number value)
  "Encode a float field (wire type 5, fixed 32-bit little-endian).
Omits when VALUE is NIL or numerically zero (proto3 default)."
  (when (and value (or (not (numberp value)) (not (zerop value))))
    (let* ((bits (%single-float-to-u32 value))
           (bytes (make-array 4 :element-type '(unsigned-byte 8))))
      (dotimes (i 4)
        (setf (aref bytes i) (ldb (byte 8 (* i 8)) bits)))
      (concatenate '(simple-array (unsigned-byte 8) (*))
                   (encode-tag field-number 5)
                   bytes))))

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

(defun field-double (fields field-number &optional (default 0.0d0))
  "Retrieve a double field from decoded fields (wire type 1)."
  (let ((raw (field-value fields field-number)))
    (if (and raw
             (typep raw '(simple-array (unsigned-byte 8) (*)))
             (>= (length raw) 8))
        (let ((bits 0))
          (dotimes (i 8)
            (setf bits (logior bits (ash (aref raw i) (* i 8)))))
          (%u64-to-double-float bits))
        default)))

(defun field-float (fields field-number &optional (default 0.0))
  "Retrieve a float field from decoded fields (wire type 5)."
  (let ((raw (field-value fields field-number)))
    (if (and raw
             (typep raw '(simple-array (unsigned-byte 8) (*)))
             (>= (length raw) 4))
        (let ((bits 0))
          (dotimes (i 4)
            (setf bits (logior bits (ash (aref raw i) (* i 8)))))
          (%u32-to-single-float bits))
        default)))

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

(defun encode-map-string-submessage (field-number alist encode-fn)
  "Encode an alist of (key . value) map entries as a message map."
  (when alist
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (loop for (key . val) in alist
                 for value-bytes = (if (typep val '(simple-array (unsigned-byte 8) (*)))
                                      val
                                      (funcall encode-fn val))
                 for entry = (concatenate '(simple-array (unsigned-byte 8) (*))
                                          (encode-field-string 1 (princ-to-string key))
                                          (encode-field-submessage 2 value-bytes))
                 when (plusp (length entry))
                   collect (encode-field-submessage field-number entry)))))

(defun decode-map-string-submessage (fields field-number decode-fn)
  "Decode repeated submessage entries at FIELD-NUMBER as an alist of string keys and decoded values."
  (loop for (fn . val) in fields
        when (and (= fn field-number)
                  (typep val '(simple-array (unsigned-byte 8) (*))))
        collect (let ((sub (decode-fields val)))
                  (cons (field-string sub 1)
                        (funcall decode-fn (field-bytes sub 2))))))

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
          :sequence-number     (field-int f 5 0)
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
                                           (+ (ash 1 64) priority)
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

(defun encode-shutdown-agent-request (agent-id &optional grace-period-seconds grace-period-nanos)
  "Encode a ShutdownAgentRequest.
Field 1 = agent_id, field 2 = google.protobuf.Duration grace_period."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (when (or grace-period-seconds grace-period-nanos)
                  (let ((duration (concatenate '(simple-array (unsigned-byte 8) (*))
                                               (encode-field-varint 1 (or grace-period-seconds 0))
                                               (encode-field-varint 2 (or grace-period-nanos 0)))))
                    (encode-field-submessage 2 duration))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

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
                ;; field 3 = double confidence_score
                (encode-field-double 3 (getf evaluation :confidence-score))
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
  "Decode a ParallelismCheckResponse."
  (let ((f (decode-fields buffer)))
    (list :confidence-score (field-double f 1 0.0d0)
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
    (list :confidence-score (field-double f 1 0.0d0)
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
          :cost-cents  (field-double f 3 0.0d0)
          :model       (field-string f 4))))

;;; -----------------------------------------------------------------------
;;;  Workflow codecs  (workflow.proto)
;;; -----------------------------------------------------------------------

(defun workflow-trigger-type-code (value)
  "Convert workflow trigger type values between plist and wire representation."
  (etypecase value
    (integer value)
    (keyword (case value
               (:event 1)
               (:schedule 2)
               (:manual 3)
               (:dependency 4)
               (otherwise 0)))
    (string (case (string-upcase value)
              ("EVENT" 1)
              ("SCHEDULE" 2)
              ("MANUAL" 3)
              ("DEPENDENCY" 4)
              (otherwise 0)))))

(defun decode-workflow-trigger-type (value)
  (case value
    (1 :event)
    (2 :schedule)
    (3 :manual)
    (4 :dependency)
    (otherwise :unspecified)))

(defun workflow-node-status-code (value)
  "Convert workflow node status values between plist and wire representation."
  (etypecase value
    (integer value)
    (keyword (case value
               (:pending 1)
               (:ready 2)
               (:running 3)
               (:completed 4)
               (:failed 5)
               (:skipped 6)
               (otherwise 0)))
    (string (case (string-upcase value)
              ("PENDING" 1)
              ("READY" 2)
              ("RUNNING" 3)
              ("COMPLETED" 4)
              ("FAILED" 5)
              ("SKIPPED" 6)
              (otherwise 0)))))

(defun decode-workflow-node-status (value)
  (case value
    (1 :pending)
    (2 :ready)
    (3 :running)
    (4 :completed)
    (5 :failed)
    (6 :skipped)
    (otherwise :unspecified)))

(defun encode-workflow-node (node)
  "Encode a WorkflowNode message."
  (let ((parts (list
                (encode-field-string 1 (getf node :node-id))
                (encode-field-string 2 (getf node :agent-id))
                (when (getf node :dependencies)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (dep) (encode-field-string 3 dep))
                                 (getf node :dependencies))))
                (encode-field-varint 4 (workflow-trigger-type-code (getf node :trigger-type)))
                (encode-map-string-string 5 (getf node :input-mapping))
                (encode-map-string-string 6 (getf node :output-mapping))
                (encode-map-string-string 7 (getf node :metadata)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-workflow-node (buffer)
  "Decode a WorkflowNode message."
  (let ((f (decode-fields buffer)))
    (list :node-id (field-string f 1)
          :agent-id (field-string f 2)
          :dependencies (field-repeated-strings f 3)
          :trigger-type (decode-workflow-trigger-type (field-int f 4 0))
          :input-mapping (decode-map-string-string f 5)
          :output-mapping (decode-map-string-string f 6)
          :metadata (decode-map-string-string f 7))))

(defun encode-workflow-node-state (state)
  "Encode a WorkflowNodeState message."
  (let ((parts (list
                (encode-field-string 1 (getf state :node-id))
                (encode-field-varint 2 (workflow-node-status-code (getf state :status)))
                (encode-field-bytes 3 (%bytes-from-text-or-bytes (getf state :started-at)))
                (encode-field-bytes 4 (%bytes-from-text-or-bytes (getf state :completed-at)))
                (encode-field-string 5 (getf state :output))
                (encode-field-string 6 (getf state :error)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-workflow-node-state (buffer)
  "Decode a WorkflowNodeState message."
  (let ((f (decode-fields buffer)))
    (list :node-id (field-string f 1)
          :status (decode-workflow-node-status (field-int f 2 0))
          :started-at (field-bytes f 3)
          :completed-at (field-bytes f 4)
          :output (field-string f 5)
          :error (field-string f 6))))

(defun encode-workflow-definition (definition)
  "Encode a WorkflowDefinition message."
  (let ((parts (list
                (encode-field-string 1 (getf definition :workflow-id))
                (encode-map-string-submessage 2 (getf definition :nodes)
                                            #'encode-workflow-node)
                (encode-field-bytes 3 (%bytes-from-text-or-bytes (getf definition :created-at)))
                (encode-map-string-string 4 (getf definition :metadata)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-workflow-definition (buffer)
  "Decode a WorkflowDefinition message."
  (let ((f (decode-fields buffer)))
    (list :workflow-id (field-string f 1)
          :nodes (decode-map-string-submessage f 2 #'decode-workflow-node)
          :created-at (field-bytes f 3)
          :metadata (decode-map-string-string f 4))))

(defun encode-workflow-state (state)
  "Encode a WorkflowState message."
  (let ((parts (list
                (encode-field-string 1 (getf state :workflow-id))
                (encode-map-string-submessage 2 (getf state :node-states)
                                            #'encode-workflow-node-state)
                (encode-field-string 3 (getf state :workflow-data))
                (encode-field-bytes 4 (%bytes-from-text-or-bytes (getf state :started-at)))
                (encode-field-bytes 5 (%bytes-from-text-or-bytes (getf state :completed-at)))
                (encode-map-string-string 6 (getf state :metadata)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-workflow-state (buffer)
  "Decode a WorkflowState message."
  (let ((f (decode-fields buffer)))
    (list :workflow-id (field-string f 1)
          :node-states (decode-map-string-submessage f 2 #'decode-workflow-node-state)
          :workflow-data (field-string f 3)
          :started-at (field-bytes f 4)
          :completed-at (field-bytes f 5)
          :metadata (decode-map-string-string f 6))))

(defun encode-create-workflow-request (definition)
  "Encode a CreateWorkflowRequest: field 1 = WorkflowDefinition submessage."
  (let ((def-bytes (or (encode-workflow-definition definition)
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
          :state (let ((state-bytes (field-bytes f 2)))
                   (if (plusp (length state-bytes))
                       (decode-workflow-state state-bytes)
                       nil))
          :success     (not (zerop (field-int f 3 0)))
          :error       (field-string f 4))))

(defun encode-get-workflow-state-request (workflow-id)
  "Encode a GetWorkflowStateRequest: field 1 = workflow_id."
  (or (encode-field-string 1 workflow-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-workflow-state-response (buffer)
  "Decode a GetWorkflowStateResponse."
  (let ((f (decode-fields buffer)))
    (list :state (let ((state-bytes (field-bytes f 1)))
                  (if (plusp (length state-bytes))
                      (decode-workflow-state state-bytes)
                      nil))
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
          :state (let ((state-bytes (field-bytes f 2)))
                   (if (plusp (length state-bytes))
                       (decode-workflow-state state-bytes)
                       nil))
          :success     (not (zerop (field-int f 3 0)))
          :error       (field-string f 4))))

;;; -----------------------------------------------------------------------
;;;  Scheduler Policy codecs  (scheduler_policy.proto)
;;; -----------------------------------------------------------------------

(defun encode-policy-hitl (hitl)
  "Encode a NegotiationPolicy.Hitl message."
  (let ((parts (list (encode-field-string 1 (getf hitl :mode)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-policy-hitl (buffer)
  "Decode a NegotiationPolicy.Hitl message."
  (let ((f (decode-fields buffer)))
    (list :mode (field-string f 1))))

(defun encode-policy-scoring (scoring)
  "Encode a NegotiationPolicy.Scoring message."
  (let ((parts (list
                (encode-field-bool 1 (getf scoring :require-schema-valid))
                (encode-field-bool 2 (getf scoring :require-examples-pass))
                (encode-field-float 3 (getf scoring :llm-weight)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-policy-scoring (buffer)
  "Decode a NegotiationPolicy.Scoring message."
  (let ((f (decode-fields buffer)))
    (list :require-schema-valid (not (zerop (field-int f 1 0)))
          :require-examples-pass (not (zerop (field-int f 2 0)))
          :llm-weight (field-float f 3 0.0))))

(defun encode-negotiation-policy (policy)
  "Encode a NegotiationPolicy message."
  (let ((parts
          (list
           (encode-field-varint 1 (getf policy :max-rounds))
           (encode-field-float 2 (getf policy :score-threshold))
           (encode-field-float 3 (getf policy :diff-tolerance))
           (encode-field-varint 4 (getf policy :round-timeout-ms))
           (encode-field-varint 5 (getf policy :token-budget-per-round))
           (encode-field-varint 6 (getf policy :total-token-budget))
           (encode-field-varint 7 (getf policy :oscillation-limit))
           (when (getf policy :hitl)
             (encode-field-submessage
              8
              (let ((hitl (getf policy :hitl)))
                (if (typep hitl '(simple-array (unsigned-byte 8) (*)))
                    hitl
                    (encode-policy-hitl hitl)))))
           (when (getf policy :scoring)
             (encode-field-submessage
              9
              (let ((scoring (getf policy :scoring)))
                (if (typep scoring '(simple-array (unsigned-byte 8) (*)))
                    scoring
                    (encode-policy-scoring scoring))))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-negotiation-policy (buffer)
  "Decode a NegotiationPolicy message."
  (let ((f (decode-fields buffer)))
    (list :max-rounds (field-int f 1 0)
          :score-threshold (field-float f 2 0.0)
          :diff-tolerance (field-float f 3 0.0)
          :round-timeout-ms (field-int f 4 0)
          :token-budget-per-round (field-int f 5 0)
          :total-token-budget (field-int f 6 0)
          :oscillation-limit (field-int f 7 0)
          :hitl (let ((hitl-bytes (field-bytes f 8)))
                  (if (plusp (length hitl-bytes))
                      (decode-policy-hitl hitl-bytes)
                      nil))
          :scoring (let ((scoring-bytes (field-bytes f 9)))
                     (if (plusp (length scoring-bytes))
                         (decode-policy-scoring scoring-bytes)
                         nil)))))

(defun encode-agent-preferences (prefs)
  "Encode an AgentPreferences message."
  (let ((parts (list
                (encode-field-varint 1 (getf prefs :max-rounds))
                (encode-field-float 2 (getf prefs :score-threshold))
                (encode-field-float 3 (getf prefs :diff-tolerance))
                (encode-field-varint 4 (getf prefs :round-timeout-ms))
                (encode-field-varint 5 (getf prefs :token-budget-per-round))
                (encode-field-varint 6 (getf prefs :total-token-budget))
                (encode-field-varint 7 (getf prefs :oscillation-limit)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-agent-preferences (buffer)
  "Decode an AgentPreferences message."
  (let ((f (decode-fields buffer)))
    (list :max-rounds (field-int f 1 0)
          :score-threshold (field-float f 2 0.0)
          :diff-tolerance (field-float f 3 0.0)
          :round-timeout-ms (field-int f 4 0)
          :token-budget-per-round (field-int f 5 0)
          :total-token-budget (field-int f 6 0)
          :oscillation-limit (field-int f 7 0))))

(defun encode-policy-profile (profile)
  "Encode a PolicyProfile message."
  (let ((parts (list
                (encode-field-string 1 (getf profile :name))
                (encode-field-submessage
                 2
                 (let ((policy (getf profile :policy)))
                   (if (typep policy '(simple-array (unsigned-byte 8) (*)))
                       policy
                       (encode-negotiation-policy policy)))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-policy-profile (buffer)
  "Decode a PolicyProfile message."
  (let ((f (decode-fields buffer)))
    (list :name (field-string f 1)
          :policy (let ((policy-bytes (field-bytes f 2)))
                    (if (plusp (length policy-bytes))
                        (decode-negotiation-policy policy-bytes)
                        nil)))))

(defun encode-delta-summary (delta)
  "Encode an EvaluationReport.DeltaSummary message."
  (let ((parts (list
                (encode-field-float 1 (getf delta :magnitude))
                (when (getf delta :changed-paths)
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (path) (encode-field-string 2 path))
                                 (getf delta :changed-paths)))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-delta-summary (buffer)
  "Decode an EvaluationReport.DeltaSummary message."
  (let ((f (decode-fields buffer)))
    (list :magnitude (field-float f 1 0.0)
          :changed-paths (loop for (fn . val) in f
                               when (= fn 2)
                               collect (field-string (list (cons 2 val)) 2)))))

(defun encode-policy-evaluation-report (report)
  "Encode an EvaluationReport message."
  (let ((parts
          (list
           (encode-field-string 1 (getf report :from-agent))
           (encode-field-float 2 (getf report :deterministic-score))
           (encode-field-float 3 (getf report :llm-confidence))
           (encode-field-string 4 (getf report :notes))
           (when (getf report :delta)
             (encode-field-submessage
              5
              (let ((delta (getf report :delta)))
                (if (typep delta '(simple-array (unsigned-byte 8) (*)))
                    delta
                    (encode-delta-summary delta))))))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-policy-evaluation-report (buffer)
  "Decode an EvaluationReport message."
  (let ((f (decode-fields buffer)))
    (list :from-agent (field-string f 1)
          :deterministic-score (field-float f 2 0.0)
          :llm-confidence (field-float f 3 0.0)
          :notes (field-string f 4)
          :delta (let ((delta-bytes (field-bytes f 5)))
                   (if (plusp (length delta-bytes))
                       (decode-delta-summary delta-bytes)
                       nil)))))

(defun encode-effective-policy (effective)
  "Encode an EffectivePolicy message."
  (let ((parts (list
                (encode-field-submessage
                 1
                 (let ((policy (getf effective :policy)))
                   (if (typep policy '(simple-array (unsigned-byte 8) (*)))
                       policy
                       (encode-negotiation-policy policy))))
                (encode-map-string-submessage
                 2
                 (getf effective :applied)
                 #'encode-agent-preferences))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-effective-policy (buffer)
  "Decode an EffectivePolicy message."
  (let ((f (decode-fields buffer)))
    (list :policy (let ((policy-bytes (field-bytes f 1)))
                   (if (plusp (length policy-bytes))
                       (decode-negotiation-policy policy-bytes)
                       nil))
          :applied (decode-map-string-submessage f 2 #'decode-agent-preferences))))

(defun encode-set-negotiation-policy-request (policy)
  "Encode a SetNegotiationPolicyRequest: field 1 = NegotiationPolicy submessage.
POLICY can be already-encoded bytes or a NegotiationPolicy plist."
  (encode-field-submessage 1 (if (typep policy '(simple-array (unsigned-byte 8) (*)))
                               policy
                               (encode-negotiation-policy policy))))

(defun decode-set-negotiation-policy-response (buffer)
  "Decode: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-set-policy-profiles-request (profiles)
  "Encode a SetPolicyProfilesRequest: repeated PolicyProfile submessages at field 1."
  (if (typep profiles '(simple-array (unsigned-byte 8) (*)))
      profiles
      (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
             (remove nil
                     (mapcar (lambda (profile)
                               (let ((encoded (if (typep profile '(simple-array (unsigned-byte 8) (*)))
                                                  profile
                                                  (encode-policy-profile profile))))
                                 (when encoded
                                   (encode-field-submessage 1 encoded))))
                             profiles)))))

(defun decode-set-policy-profiles-response (buffer)
  "Decode: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-get-negotiation-policy-request ()
  "Encode a GetNegotiationPolicyRequest (empty message)."
  (make-array 0 :element-type '(unsigned-byte 8)))

(defun decode-get-negotiation-policy-response (buffer)
  "Decode: field 1 = NegotiationPolicy submessage."
  (let ((f (decode-fields buffer)))
    (let ((policy-bytes (field-bytes f 1)))
      (if (plusp (length policy-bytes))
          (list :policy (decode-negotiation-policy policy-bytes))
          (list :policy nil)))))

(defun decode-list-policy-profiles-response (buffer)
  "Decode a ListPolicyProfilesResponse: repeated PolicyProfile at field 1."
  (loop for (fn . val) in (decode-fields buffer)
        when (and (= fn 1)
                  (typep val '(simple-array (unsigned-byte 8) (*)))
                  (plusp (length val)))
        collect (decode-policy-profile val)))

(defun encode-get-effective-policy-request (negotiation-id)
  "Encode a GetEffectivePolicyRequest: field 1 = negotiation_id."
  (or (encode-field-string 1 negotiation-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-effective-policy-response (buffer)
  "Decode: field 1 = EffectivePolicy submessage (raw bytes)."
  (let ((f (decode-fields buffer)))
    (let ((effective-bytes (field-bytes f 1)))
      (if (plusp (length effective-bytes))
          (list :effective (decode-effective-policy effective-bytes))
          (list :effective nil)))))

(defun encode-submit-evaluation-request (negotiation-id report-bytes)
  "Encode a SubmitEvaluationRequest.
REPORT-BYTES can be already-encoded bytes or an EvaluationReport plist."
  (let ((parts (list
                (encode-field-string 1 negotiation-id)
                (encode-field-submessage
                 2
                 (let ((bytes report-bytes))
                   (if (typep bytes '(simple-array (unsigned-byte 8) (*)))
                       bytes
                       (encode-policy-evaluation-report bytes)))))))
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

;;; -----------------------------------------------------------------------
;;;  I61 tranche completion codecs (proto-backed stubs)
;;; -----------------------------------------------------------------------

;;; Scheduler codecs (additional endpoints)

(defun encode-cancel-task-request (agent-id task-id &optional reason)
  "Encode a CancelTaskRequest.
FIELD 1 = agent_id, FIELD 2 = task_id, FIELD 3 = reason(optional)."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 task-id)
                (encode-field-string 3 reason))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-cancel-task-response (buffer)
  "Decode a CancelTaskResponse.
FIELD 1 = cancelled (bool), FIELD 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :cancelled (not (zerop (field-int f 1 0)))
          :reason    (field-string f 2))))

(defun encode-get-task-status-request (agent-id task-id)
  "Encode a GetTaskStatusRequest.
FIELD 1 = agent_id, FIELD 2 = task_id."
  (let ((parts (list
                (encode-field-string 1 agent-id)
                (encode-field-string 2 task-id))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-task-status-response (buffer)
  "Decode a GetTaskStatusResponse.
FIELD 1 = task-id, FIELD 2 = status, FIELD 3 = progress,
FIELD 4 = message, FIELD 5 = started_at, FIELD 6 = completed_at."
  (let ((f (decode-fields buffer)))
    (list :task-id      (field-string f 1)
          :status       (field-int f 2 0)
          :progress     (field-double f 3 0.0d0)
          :message      (field-string f 4)
          :started-at   (field-string f 5)
          :completed-at (field-string f 6))))

;;; Negotiation codecs

(defun encode-get-session-request (negotiation-id)
  "Encode a GetSessionRequest: field 1 = negotiation_id."
  (or (encode-field-string 1 negotiation-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-session-response (buffer)
  "Decode a GetSessionResponse.
FIELD 1 = negotiation_id, 2=status, 3=participants(repeated),
4=proposals(bytes),5=evaluations(bytes),6=decision(bytes)."
  (let ((f (decode-fields buffer)))
    (list :negotiation-id (field-string f 1)
          :status        (field-int f 2 0)
          :participants  (field-repeated-strings f 3)
          :proposals     (loop for (fn . val) in f
                              when (and (= fn 4)
                                        (typep val '(simple-array (unsigned-byte 8) (*)))
                                        (plusp (length val)))
                              collect val)
          :evaluations   (loop for (fn . val) in f
                              when (and (= fn 5)
                                        (typep val '(simple-array (unsigned-byte 8) (*)))
                                        (plusp (length val)))
                              collect val)
          :decision      (field-bytes f 6))))

;;; HITL codecs

(defun encode-hitl-response-request (decision-id selected-option notes)
  "Encode a HitlResponseRequest.
FIELD 1 = decision_id, FIELD 2 = selected_option, FIELD 3 = notes(optional)."
  (let ((parts (list
                (encode-field-string 1 decision-id)
                (encode-field-string 2 selected-option)
                (encode-field-string 3 notes))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-hitl-response-response (buffer)
  "Decode a HitlResponseResponse.
FIELD 1 = recorded (bool), FIELD 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :recorded (not (zerop (field-int f 1 0)))
          :reason   (field-string f 2))))

(defun encode-hitl-pending-request (operator-id)
  "Encode a HitlPendingRequest.
FIELD 1 = optional operator_id filter."
  (or (encode-field-string 1 operator-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-hitl-pending-entry (buffer)
  "Decode a HitlPendingEntry submessage."
  (let ((f (decode-fields buffer)))
    (list :decision-id    (field-string f 1)
          :correlation-id (field-string f 2)
          :reason-type    (field-int f 3 0)
          :context        (field-string f 4)
          :status         (field-int f 5 0)
          :created-at     (field-string f 6)
          :timeout-at     (field-string f 7))))

(defun decode-hitl-pending-response (buffer)
  "Decode a HitlPendingResponse: field 1 = repeated HitlPendingEntry."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1)
                    (typep val '(simple-array (unsigned-byte 8) (*)))
                    (plusp (length val)))
          collect (decode-hitl-pending-entry val))))

(defun encode-hitl-decision-status-request (decision-id)
  "Encode a HitlDecisionStatusRequest.
FIELD 1 = decision_id."
  (or (encode-field-string 1 decision-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-hitl-decision-status-response (buffer)
  "Decode a HitlDecisionStatusResponse.
FIELD 1 = decision_id, FIELD 2 = status, FIELD 3 = selected_option,
FIELD 4 = notes, FIELD 5 = decided_at."
  (let ((f (decode-fields buffer)))
    (list :decision-id     (field-string f 1)
          :status          (field-int f 2 0)
          :selected-option (field-string f 3)
          :notes           (field-string f 4)
          :decided-at      (field-string f 5))))

;;; Logging codecs

(defun encode-query-logs-request (&key correlation-id agent-id level start-time end-time
                                  tags limit)
  "Encode a QueryLogsRequest.
FIELD map:
1=correlation_id,2=agent_id,3=level,4=start_time,5=end_time,
6=tags(repeated),7=limit."
  (let ((parts (list
                (encode-field-string 2 correlation-id)
                (encode-field-string 3 agent-id)
                (encode-field-string 4 (cond
                                        ((null level) nil)
                                        ((keywordp level) (string-downcase (string level)))
                                        (t (princ-to-string level))))
                (encode-field-string 5 (or start-time ""))
                (encode-field-string 6 (or end-time ""))
                (when tags
                  (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
                         (mapcar (lambda (tag) (encode-field-string 7 tag)) tags)))
                (encode-field-varint 8 (or limit 0)))))
    (apply #'concatenate '(simple-array (unsigned-byte 8) (*))
           (remove nil parts))))

(defun decode-log-event-entry (buffer)
  "Decode a LogEvent entry used by query responses."
  (let ((f (decode-fields buffer)))
    (list :correlation-id (field-string f 2)
          :agent-id       (field-string f 3)
          :event-type     (field-string f 4)
          :level          (field-string f 5)
          :details-json   (field-string f 6)
          :message        (field-string f 6))))

(defun decode-query-logs-response (buffer)
  "Decode a QueryLogsResponse: field 1 = repeated LogEvent."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1)
                    (typep val '(simple-array (unsigned-byte 8) (*)))
                    (plusp (length val)))
          collect (decode-log-event-entry val))))

;;; Connector codecs

(defun encode-list-providers-request ()
  "Encode a ListProvidersRequest (empty message)."
  (make-array 0 :element-type '(unsigned-byte 8)))

(defun decode-provider-entry (buffer)
  "Decode a Provider entry in ListProvidersResponse."
  (let ((f (decode-fields buffer)))
    (list :provider-id    (field-string f 1)
          :registered-at  (field-string f 2)
          :tool-count     (field-int f 3 0))))

(defun decode-list-providers-response (buffer)
  "Decode a ListProvidersResponse: field 1 = repeated provider entry."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1)
                    (typep val '(simple-array (unsigned-byte 8) (*)))
                    (plusp (length val)))
          collect (decode-provider-entry val))))

;;; Activity codecs

(defun encode-deregister-activity-request (artifact-id)
  "Encode a RemoveArtifactRequest: field 1 = artifact_id."
  (or (encode-field-string 1 artifact-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-deregister-activity-response (buffer)
  "Decode a RemoveArtifactResponse: field 1 = ok, field 2 = reason."
  (let ((f (decode-fields buffer)))
    (list :ok     (not (zerop (field-int f 1 0)))
          :reason (field-string f 2))))

(defun encode-get-artifact-request (artifact-id)
  "Encode a GetArtifactRequest: field 1 = artifact_id."
  (or (encode-field-string 1 artifact-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-get-artifact-response (buffer)
  "Decode a GetArtifactResponse: field 1 = Artifact submessage."
  (decode-artifact (field-bytes (decode-fields buffer) 1)))

;;; Tool codecs

(defun encode-list-tools-request (&optional provider-id)
  "Encode a ListToolsRequest.
FIELD 1 = optional provider_id filter."
  (or (encode-field-string 1 provider-id)
      (make-array 0 :element-type '(unsigned-byte 8))))

(defun decode-list-tools-response (buffer)
  "Decode a ListToolsResponse: field 1 = repeated ToolDescriptor."
  (let ((f (decode-fields buffer)))
    (loop for (fn . val) in f
          when (and (= fn 1)
                    (typep val '(simple-array (unsigned-byte 8) (*)))
                    (plusp (length val)))
          collect (decode-tool-descriptor val))))
