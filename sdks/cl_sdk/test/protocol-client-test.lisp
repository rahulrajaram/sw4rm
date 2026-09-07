(in-package :sw4rm-test)

(def-suite protocol-client-suite :in sw4rm-suite)
(in-suite protocol-client-suite)

(defun wire-contract-data ()
  ;; CL-JSON decodes JSON reals with *READ-DEFAULT-FLOAT-FORMAT*, whose
  ;; default (single-float) truncates corpus doubles (e.g. 0.1) to 32 bits
  ;; and breaks double-field byte equality (R25).  Bind it to double-float
  ;; so the fixture builder sees the wire-precision values.
  (let ((*read-default-float-format* 'double-float))
    ;; Corpus is stored gzip-compressed (wire_vectors.json.gz); gunzip it
    ;; through the gzip CLI into a string and decode from that.
    (let* ((source (merge-pathnames #P"../../tests/conformance_vectors/wire_vectors.json.gz"
                                    (asdf:system-source-directory :sw4rm-sdk)))
           (json-text (uiop:run-program (list "gzip" "-dc" (namestring source))
                                        :output :string)))
      (with-input-from-string (stream json-text)
        (json:decode-json stream))))

(defun wire-json-message (name value)
  (loop for field in (sw4rm-sdk::protocol-message-fields name)
        for key = (first field)
        for json-key = (substitute #\_ #\- (string-downcase (symbol-name key)))
        for raw = (%json-object-get value json-key :wire-missing)
        unless (eq raw :wire-missing) append
        (list key (cond
                    ((sixth field)
                     (let ((value-field (assoc :value (sw4rm-sdk::protocol-message-fields (fifth field)))))
                       (mapcar (lambda (entry)
                                 (cons (string-downcase (symbol-name (car entry)))
                                       (wire-json-scalar value-field (cdr entry)))) raw)))
                    ((fourth field) (mapcar (lambda (item) (wire-json-scalar field item))
                                           (%json-array->list raw)))
                    (t (wire-json-scalar field raw))))))

(defun wire-json-scalar (field value)
  (case (third field)
    (:bytes (ironclad:hex-string-to-byte-array value))
    ((:int64 :uint64) (parse-integer value))
    ;; The corpus stores float32 values widened (0.10000000149011612); decode
    ;; yields single-floats and equalp is float-type-sensitive, so coerce
    ;; :float fields down to wire precision before comparing (R25).
    ((:float) (coerce value 'single-float))
    (:message (wire-json-message (fifth field) value))
    (otherwise value)))

(test canonical-message-vectors
  "Compare Lisp encoding and decoding to the Python protobuf implementation."
  (dolist (vector (%json-array->list (%json-object-get (wire-contract-data) "vectors")))
    (let* ((name (%json-object-get vector "type"))
           (expected (wire-json-message name (%json-object-get vector "value")))
           (wire (ironclad:hex-string-to-byte-array (%json-object-get vector "wire_hex"))))
      (is (equalp wire (sw4rm-sdk:encode-protocol-message name expected))
          "Wire encoding differs for ~A" (%json-object-get vector "id"))
      (is (equalp expected (sw4rm-sdk:decode-protocol-message name wire))
          "Wire decoding differs for ~A" (%json-object-get vector "id")))))

(test all-canonical-rpc-paths-present
  (let ((expected (mapcar (lambda (rpc) (%json-object-get rpc "path"))
                          (%json-array->list (%json-object-get (wire-contract-data) "rpcs")))))
    (is (equal (sort expected #'string<) (sort (sw4rm-sdk:protocol-rpc-paths) #'string<)))))

(test codec-skips-wire-type-mismatched-fields
  "A field whose wire type contradicts the schema is skipped as unknown."
  ;; Envelope field 2 (idempotency-token) is a string (wire type 2).  A
  ;; varint (wire type 0) under the same number must be treated as unknown
  ;; and skipped, not decoded as the string field (R37).
  (let* ((varint-under-string-field
          (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(16 42)))
         (verbose
          (make-array 4 :element-type '(unsigned-byte 8)
                      :initial-contents '(18 2 104 105))))
    (is (not (assoc :idempotency-token
                    (sw4rm-sdk:decode-protocol-message "sw4rm.common.Envelope"
                                                        varint-under-string-field)))
        "varint payload under a string field number is skipped")
    ;; Positive control: the same field number with the correct wire type
    ;; still decodes to its string value.
    (is (equal "hi" (getf (sw4rm-sdk:decode-protocol-message "sw4rm.common.Envelope"
                                                               verbose)
                           :idempotency-token))
        "correct wire type still decodes the field")
    ;; Envelope field 7 (message-type) is an enum (varint).  A
    ;; length-delimited payload under the same number must be skipped too.
    (let* ((length-under-enum-field
            (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(58 1 77))))
      (is (not (assoc :message-type
                      (sw4rm-sdk:decode-protocol-message "sw4rm.common.Envelope"
                                                          length-under-enum-field)))
          "length-delimited payload under an enum field number is skipped"))))

(test canonical-codec-rejects-invalid-data
  (dolist (contents '((10 5 65) (9 0) (13 0) (0) (8 128)
                      (8 255 255 255 255 255 255 255 255 255 2)))
    (signals error
      (sw4rm-sdk:decode-protocol-message
       "sw4rm.common.Envelope"
       (make-array (length contents) :element-type '(unsigned-byte 8) :initial-contents contents))))
  (signals error (sw4rm-sdk:encode-protocol-message "sw4rm.router.StreamRequest" '(:typo "agent")))
  (signals error (sw4rm-sdk:encode-protocol-message "sw4rm.router.DeliveryAckRequest"
                                                   (list :seq (expt 2 63)))))

(test float-codec-preserves-negative-zero-and-nan
  "Negative zero keeps its sign bit and NaN round-trips without FP traps."
  (flet ((round-trip-double (value)
           (sw4rm-sdk:decode-protocol-message
            "sw4rm.negotiation.Evaluation"
            (sw4rm-sdk:encode-protocol-message
             "sw4rm.negotiation.Evaluation" (list :confidence-score value))))
         (round-trip-float (value)
           (sw4rm-sdk:decode-protocol-message
            "sw4rm.policy.AgentPreferences"
            (sw4rm-sdk:encode-protocol-message
             "sw4rm.policy.AgentPreferences" (list :score-threshold value)))))
    ;; Positive zero is the proto3 default and stays omitted.
    (is (= 0 (length (sw4rm-sdk:encode-protocol-message
                      "sw4rm.negotiation.Evaluation"
                      (list :confidence-score 0.0d0)))))
    ;; Negative zero is emitted and decodes with its sign preserved.
    (is (minusp (float-sign (getf (round-trip-double -0.0d0) :confidence-score))))
    (is (minusp (float-sign (getf (round-trip-float -0.0f0) :score-threshold))))
    ;; NaN is emitted and round-trips as a NaN bit pattern (IEEE-754).
    #+sbcl
    (let ((bits (sb-kernel:double-float-bits
                 (getf (round-trip-double
                        (sw4rm-sdk::%u64-to-double-float #x7ff8000000000000))
                       :confidence-score))))
      (is (= #x7ff (ldb (byte 11 52) bits)))
      (is (plusp (ldb (byte 52 0) bits))))
    #+sbcl
    (let ((bits (sb-kernel:single-float-bits
                 (getf (round-trip-float
                        (sw4rm-sdk::%u32-to-single-float #x7fc00000))
                       :score-threshold))))
      (is (= #xff (ldb (byte 8 23) bits)))
      (is (plusp (ldb (byte 23 0) bits))))))

(defmacro with-protocol-unary ((channel method request deadline) response &body body)
  "Observe bytes at the transport boundary without requiring native libgrpc."
  (let ((original (gensym "ORIGINAL")))
    `(let ((,original (symbol-function 'sw4rm-sdk:grpc-unary-call)))
       (unwind-protect
            (progn
              (setf (symbol-function 'sw4rm-sdk:grpc-unary-call)
                    (lambda (,channel ,method ,request &key (deadline-ms 30000) metadata)
                      (declare (ignore metadata))
                      (let ((,deadline deadline-ms)) ,response)))
              ,@body)
         (setf (symbol-function 'sw4rm-sdk:grpc-unary-call) ,original)))))

(test scheduler-shutdown-canonical-wire
  (with-protocol-unary (channel method request deadline)
      (progn
        (is (eq :test channel))
        (is (string= "/sw4rm.scheduler.SchedulerService/ShutdownAgent" method))
        (is (= 750 deadline))
        ;; Canonical protobuf: agent_id = 1; Duration grace_period = 2.
        (let* ((fields (sw4rm-sdk::decode-fields request))
               (duration (sw4rm-sdk::decode-fields (sw4rm-sdk::field-bytes fields 2))))
          (is (string= "agent-1" (sw4rm-sdk::field-string fields 1)))
          (is (= 5 (sw4rm-sdk::field-int duration 1)))
          (is (= 500000000 (sw4rm-sdk::field-int duration 2))))
        (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(8 1)))
    (let ((client (make-instance 'sw4rm-sdk:scheduler-client
                                 :address "unused" :channel :test :timeout-ms 750)))
      (is (getf (sw4rm-sdk:shutdown-agent client "agent-1"
                                        :grace-period-seconds 5
                                        :grace-period-nanos 500000000) :ok)))))

(test workflow-start-canonical-wire
  (with-protocol-unary (channel method request deadline)
      (progn
        (is (eq :test channel))
        (is (string= "/sw4rm.workflow.WorkflowService/StartWorkflow" method))
        (is (= 900 deadline))
        (let ((fields (sw4rm-sdk::decode-fields request)))
          (is (string= "wf-1" (sw4rm-sdk::field-string fields 1)))
          (is (string= "{\"input\":1}" (sw4rm-sdk::field-string fields 2)))
          (is (equal '(("trace" . "test"))
                     (sw4rm-sdk::decode-map-string-string fields 3))))
        (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(24 1)))
    (let ((client (make-instance 'sw4rm-sdk:workflow-client
                                 :address "unused" :channel :test :timeout-ms 900)))
      (is (getf (sw4rm-sdk:start-workflow client "wf-1" :workflow-data "{\"input\":1}"
                                        :metadata '(("trace" . "test"))) :success)))))

(defmacro with-protocol-stream ((channel method request deadline) response &body body)
  "Observe stream establishment at the transport boundary without libgrpc.
RESPONSE is evaluated inside the transport lambda with DEADLINE bound, once
per stream establishment; BODY runs afterwards."
  (let ((original (gensym "ORIGINAL")))
    `(let ((,original (symbol-function 'sw4rm-sdk:grpc-server-stream)))
       (unwind-protect
            (progn
              (setf (symbol-function 'sw4rm-sdk:grpc-server-stream)
                    (lambda (,channel ,method ,request callback &key (deadline-ms 0) metadata)
                      (declare (ignore callback metadata))
                      (let ((,deadline deadline-ms))
                        ,response
                        (list :fake-stream))))
              ,@body)
         (setf (symbol-function 'sw4rm-sdk:grpc-server-stream) ,original)))))

(test stream-deadline-is-independent-of-client-timeout
  "Streams default to no deadline (long-lived subscriptions), never the unary timeout."
  (let ((seen-deadlines nil))
    (flet ((noop-handler (message) (declare (ignore message))))
      (with-protocol-stream (%channel %method %request deadline)
          (push deadline seen-deadlines)
          (list :fake-stream)
        (let ((client (make-instance 'sw4rm-sdk:protocol-client
                                     :address "unused" :channel :test :timeout-ms 30000)))
          ;; Default: no deadline (0), not the client-wide 30s unary timeout.
          (sw4rm-sdk:stream-protocol-rpc
           client "/sw4rm.router.RouterService/StreamIncoming"
           '(:agent-id "agent-1") #'noop-handler)
          ;; Explicit per-call override passes through.
          (sw4rm-sdk:stream-protocol-rpc
           client "/sw4rm.router.RouterService/StreamIncoming"
           '(:agent-id "agent-1") #'noop-handler :deadline-ms 45000)
          (is (equal '(0 45000) (nreverse seen-deadlines))))))))

(defun wire-vector-message (name variant)
  (let ((vector (find (format nil "~A:~A" name variant)
                      (%json-array->list (%json-object-get (wire-contract-data) "vectors"))
                      :test #'string= :key (lambda (item) (%json-object-get item "id")))))
    (unless vector (error "Missing wire vector: ~A/~A" name variant))
    (wire-json-message name (%json-object-get vector "value"))))

(defun wire-normalize-message (name message)
  "Map entry ordering has no protobuf meaning; repeated message ordering does."
  (loop for (key value) on message by #'cddr
        for field = (assoc key (sw4rm-sdk::protocol-message-fields name))
        append (list key
                     (cond
                       ((sixth field)
                        (let ((value-field (assoc :value (sw4rm-sdk::protocol-message-fields (fifth field)))))
                          (sort (mapcar (lambda (entry)
                                          (cons (car entry)
                                                (if (eq :message (third value-field))
                                                    (wire-normalize-message (fifth value-field) (cdr entry))
                                                    (cdr entry)))) value)
                                #'string< :key #'car)))
                       ((eq :message (third field))
                        (if (fourth field)
                            (mapcar (lambda (item) (wire-normalize-message (fifth field) item)) value)
                            (wire-normalize-message (fifth field) value)))
                       (t value)))))

(test canonical-rpcs-against-python
  "Exercise every canonical method over libgrpc, including streaming and metadata."
  (let ((target (uiop:getenv "SW4RM_WIRE_TARGET")))
    (if (not target)
        (skip "Set SW4RM_WIRE_TARGET using tests/sdk_parity/with_wire_server.py")
        (let ((client (make-instance 'sw4rm-sdk:protocol-client :address target :timeout-ms 3000)))
          (unwind-protect
               (dolist (rpc sw4rm-sdk::*protocol-rpc-schemas*)
                 (destructuring-bind (path request-type response-type streaming) rpc
                   (dolist (variant '("sample" "edge"))
                     (let ((request (wire-vector-message request-type variant))
                           (metadata (list (cons "sw4rm-vector" variant))))
                       (if streaming
                           (let* ((responses nil)
                                  (handle (sw4rm-sdk:stream-protocol-rpc
                                           client path request (lambda (response) (push response responses))
                                           :metadata metadata)))
                             (sw4rm-sdk:wait-for-stream handle)
                             (is (equalp (list (wire-vector-message response-type "sample")
                                              (wire-vector-message response-type "edge") nil)
                                         (nreverse responses)) "~A (~A)" path variant)
                             ;; Cancellation after completion must never touch freed native memory.
                             (sw4rm-sdk:cancel-stream handle))
                           (is (equalp (wire-normalize-message response-type (wire-vector-message response-type variant))
                                       (wire-normalize-message response-type
                                         (sw4rm-sdk:call-protocol-rpc client path request :metadata metadata)))
                               "~A (~A)" path variant))))))
            (sw4rm-sdk:disconnect client))))))

(test native-slices-round-trip
  (when sw4rm-sdk::*grpc-available*
    (dolist (size '(0 1 23 24 256 65536))
      (let* ((bytes (make-array size :element-type '(unsigned-byte 8)
                                    :initial-contents (loop for i below size collect (mod i 256))))
             (buffer (sw4rm-sdk::bytes-to-grpc-byte-buffer bytes)))
        (unwind-protect
             (is (equalp bytes (sw4rm-sdk::grpc-byte-buffer-to-bytes buffer)))
          (sw4rm-sdk::grpc-byte-buffer-destroy buffer))))))

(test native-errors-deadlines-cancellation-and-concurrency
  (let ((target (uiop:getenv "SW4RM_WIRE_TARGET")))
    (if (not target)
        (skip "Requires the localhost wire oracle")
        (let* ((client (make-instance 'sw4rm-sdk:protocol-client :address target :timeout-ms 3000))
               (path "/sw4rm.router.RouterService/SendMessage")
               (request (wire-vector-message "sw4rm.router.SendMessageRequest" "sample"))
               (stream-path "/sw4rm.router.RouterService/StreamIncoming")
               (stream-request (wire-vector-message "sw4rm.router.StreamRequest" "sample")))
          (unwind-protect
               (progn
                 (handler-case
                     (progn (sw4rm-sdk:call-protocol-rpc client path request
                              :metadata '(("sw4rm-error" . "1")))
                            (fail "Remote failure was swallowed"))
                   (sw4rm-sdk:rpc-error (condition)
                     (is (string= "INVALID_ARGUMENT" (sw4rm-sdk::rpc-error-status-code condition)))
                     (is (search "requested conformance error" (sw4rm-sdk::rpc-error-details condition)))))
                 (let* ((error-stream-messages nil)
                        (handle (sw4rm-sdk:stream-protocol-rpc
                                 client stream-path stream-request
                                 (lambda (message) (push message error-stream-messages))
                                 :metadata '(("sw4rm-error" . "1")))))
                   (signals sw4rm-sdk:rpc-error (sw4rm-sdk:wait-for-stream handle))
                   ;; Error paths must not feed consumers a spurious EOF (R20).
                   (is (notany #'null error-stream-messages)))
                 (let ((handle (sw4rm-sdk:stream-protocol-rpc
                                client stream-path stream-request (lambda (message) (declare (ignore message)))
                                :metadata '(("sw4rm-hold-stream" . "1")))))
                   (sw4rm-sdk:cancel-stream handle)
                   (handler-case (sw4rm-sdk:wait-for-stream handle)
                     (sw4rm-sdk:rpc-error (condition)
                       (is (string= "CANCELLED" (sw4rm-sdk::rpc-error-status-code condition)))))
                   (is (not (null (sw4rm-sdk:stream-handle-error handle)))))
                 ;; Connect once before concurrent use; every in-flight call gets its own CQ.
                 (let* ((outcomes (make-array 8))
                        (threads (loop for i below 8 collect
                                   (let ((index i))
                                     (bordeaux-threads:make-thread
                                      (lambda ()
                                        (setf (aref outcomes index)
                                              (handler-case (sw4rm-sdk:call-protocol-rpc client path request)
                                                (error (condition) condition)))))))))
                   (mapc #'bordeaux-threads:join-thread threads)
                   (loop for outcome across outcomes do
                     (is (equalp (wire-vector-message "sw4rm.router.SendMessageResponse" "sample") outcome))))
                 (setf (sw4rm-sdk::client-timeout-ms client) 50)
                 (signals sw4rm-sdk::rpc-timeout
                   (sw4rm-sdk:call-protocol-rpc client path request :metadata '(("sw4rm-delay-ms" . "500"))))
                 (let ((handle (sw4rm-sdk:stream-protocol-rpc
                                client stream-path stream-request (lambda (message) (declare (ignore message)))
                                :deadline-ms 50
                                :metadata '(("sw4rm-hold-stream" . "1")))))
                   (signals sw4rm-sdk::rpc-timeout (sw4rm-sdk:wait-for-stream handle))))
            (sw4rm-sdk:disconnect client))))))

(test envelope-builder-preserves-wire-lineage-and-time
  (let* ((now (- (get-universal-time) 2208988800))
         (envelope (sw4rm-sdk:make-envelope :producer-id "sender" :message-type 2
                     :parent-correlation-id "parent" :timestamp '(:seconds -1 :nanos 125)
                     :sequence-number (1- (expt 2 64))))
         (decoded (sw4rm-sdk:decode-protocol-message "sw4rm.common.Envelope"
                    (sw4rm-sdk:encode-envelope envelope)))
         (hlc (getf envelope :hlc-timestamp))
         (wall (parse-integer hlc :start 4 :end (position #\: hlc :start 4))))
    (is (string= "parent" (getf decoded :parent-correlation-id)))
    (is (equal '(:seconds -1 :nanos 125) (getf decoded :timestamp)))
    (is (= (1- (expt 2 64)) (getf decoded :sequence-number)))
    (is (<= (* now 1000000) wall (* (1+ now) 1000000)))))

(test envelope-default-timestamp-has-sub-second-precision
  "A defaulted envelope timestamp carries nanos from a sub-second clock (R42)."
  #+sbcl
  (let (before-status before-seconds before-micros
        after-status after-seconds after-micros)
    (declare (ignorable before-status after-status before-micros after-micros))
    (setf (values before-status before-seconds before-micros)
          (sb-unix:unix-gettimeofday))
    (let ((envelope (sw4rm-sdk:make-envelope :producer-id "sender" :message-type 2))
          (stamp nil)
          (seconds nil)
          (nanos nil))
      (setf (values after-status after-seconds after-micros)
            (sb-unix:unix-gettimeofday))
      (setf stamp (getf envelope :timestamp))
      (setf seconds (getf stamp :seconds))
      (setf nanos (getf stamp :nanos))
      (is (<= before-seconds seconds after-seconds)
          "timestamp seconds stay within the call window")
      (is (and (integerp nanos) (<= 0 nanos 999999999))
          "nanos is a sub-second fraction")))
  #-sbcl
  (skip "sub-second wall clock requires SBCL"))

(test portable-idempotency-vectors
  (with-open-file (stream (merge-pathnames #P"../../tests/conformance_vectors/idempotency_vectors.json"
                                         (asdf:system-source-directory :sw4rm-sdk)))
    (dolist (vector (%json-array->list (%json-object-get (json:decode-json stream) "vectors")))
      (let ((producer (%json-object-get vector "producer_id"))
            (operation (%json-object-get vector "operation"))
            (canonical (ironclad:hex-string-to-byte-array (%json-object-get vector "canonical_hex"))))
        (if (%json-object-get vector "rejected")
            ;; R43: LF in producer/operation must be rejected, not hashed.
            (signals sw4rm-sdk::validation-error
              (sw4rm-sdk:compute-idempotency-token producer operation canonical))
            (is (string= (%json-object-get vector "token")
                         (sw4rm-sdk:compute-idempotency-token producer operation canonical))))))))

(test closing-channel-cancels-owned-streams
  "Disconnect immediately after subscribing, before the worker is scheduled."
  (let ((target (uiop:getenv "SW4RM_WIRE_TARGET")))
    (if (not target)
        (skip "Requires the localhost wire oracle")
        (dotimes (_ 12)
          (let* ((client (make-instance 'sw4rm-sdk:protocol-client :address target :timeout-ms 1000))
                 (handle (sw4rm-sdk:stream-protocol-rpc
                          client "/sw4rm.router.RouterService/StreamIncoming"
                          (wire-vector-message "sw4rm.router.StreamRequest" "sample")
                          (lambda (message) (declare (ignore message)))
                          :metadata '(("sw4rm-hold-stream" . "1")))))
            (sw4rm-sdk:disconnect client)
            (handler-case
                (progn (sw4rm-sdk:wait-for-stream handle) (fail "Disconnect did not cancel the stream"))
              (sw4rm-sdk:rpc-error (condition)
                (is (string= "CANCELLED" (sw4rm-sdk::rpc-error-status-code condition))))))))))

(test map-entry-omitted-value-has-protobuf-default
  ;; StartWorkflowRequest.metadata = 3; an empty map-entry message is valid.
  (is (equal '(:metadata (("" . "")))
             (sw4rm-sdk:decode-protocol-message "sw4rm.workflow.StartWorkflowRequest"
               (make-array 2 :element-type '(unsigned-byte 8) :initial-contents '(26 0))))))
