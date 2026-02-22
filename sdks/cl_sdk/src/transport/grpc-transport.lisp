;;;; grpc-transport.lisp — High-level gRPC transport API
;;;;
;;;; Wraps grpc-ffi into channel/call abstractions with proper condition
;;;; mapping, deadline support, and server-streaming via bordeaux-threads.

(in-package #:sw4rm-sdk)

;;; -----------------------------------------------------------------------
;;;  gRPC Channel wrapper
;;; -----------------------------------------------------------------------

(defclass grpc-channel ()
  ((raw-channel
    :initarg :raw-channel
    :accessor grpc-channel-raw
    :documentation "Pointer to grpc_channel*.")
   (credentials
    :initarg :credentials
    :initform nil
    :accessor grpc-channel-credentials
    :documentation "Pointer to ssl credentials (secure channels) or NIL (insecure).")
   (completion-queue
    :initarg :completion-queue
    :accessor grpc-channel-cq
    :documentation "Pointer to grpc_completion_queue* (one per channel).")
   (target
    :initarg :target
    :accessor grpc-channel-target
    :type string
    :documentation "Target address string.")
   (alive-p
    :initform t
    :accessor grpc-channel-alive-p
    :documentation "NIL after destroy-grpc-channel."))
  (:documentation "High-level wrapper around a gRPC channel + completion queue."))

(defun %normalize-grpc-target (target)
  "Normalize TARGET for libgrpc. Accepts bare host:port or http(s) URLs."
  (cond
    ((and (>= (length target) 7)
          (string-equal target "http://" :end1 7 :end2 7))
     (subseq target 7))
    ((and (>= (length target) 8)
          (string-equal target "https://" :end1 8 :end2 8))
     (subseq target 8))
    (t target)))

(defun make-grpc-channel (target &key tls)
  "Create a gRPC channel to TARGET (e.g. \"localhost:50051\").
Initialises the gRPC library if needed.

Pass :tls with root-certificate contents, a path string, or T for defaults."
  (ensure-grpc-available)
  (grpc-init)
  (let ((grpc-target (%normalize-grpc-target target)))
  (multiple-value-bind (channel credentials)
      (if tls
          (grpc-channel-create grpc-target :tls tls)
          (grpc-channel-create grpc-target))
      (make-instance 'grpc-channel
                     :raw-channel channel
                     :credentials credentials
                     :completion-queue (grpc-cq-create)
                     :target target))))

(defun destroy-grpc-channel (channel)
  "Destroy a gRPC channel and its completion queue."
  (when (and (typep channel 'grpc-channel)
             (grpc-channel-alive-p channel))
    (grpc-cq-destroy (grpc-channel-cq channel))
    (grpc-channel-destroy (grpc-channel-raw channel))
    (when (grpc-channel-credentials channel)
      (%grpc-channel-credentials-release (grpc-channel-credentials channel))
      (setf (grpc-channel-credentials channel) nil))
    (setf (grpc-channel-alive-p channel) nil)))

;;; -----------------------------------------------------------------------
;;;  Status → condition mapping
;;; -----------------------------------------------------------------------

(defun signal-grpc-status (status-code method)
  "Map a gRPC status code integer to a CL condition and signal it.
Does nothing for OK (0)."
  (unless (zerop status-code)
    (let ((status-name (case status-code
                         (1  "CANCELLED")
                         (2  "UNKNOWN")
                         (3  "INVALID_ARGUMENT")
                         (4  "DEADLINE_EXCEEDED")
                         (5  "NOT_FOUND")
                         (6  "ALREADY_EXISTS")
                         (7  "PERMISSION_DENIED")
                         (8  "RESOURCE_EXHAUSTED")
                         (9  "FAILED_PRECONDITION")
                         (10 "ABORTED")
                         (11 "OUT_OF_RANGE")
                         (12 "UNIMPLEMENTED")
                         (13 "INTERNAL")
                         (14 "UNAVAILABLE")
                         (15 "DATA_LOSS")
                         (16 "UNAUTHENTICATED")
                         (t  (format nil "UNKNOWN_~D" status-code)))))
      (cond
        ;; DEADLINE_EXCEEDED → rpc-timeout (retryable by with-retry)
        ((= status-code +grpc-status-deadline-exceeded+)
         (error 'rpc-timeout
                :message (format nil "~A: deadline exceeded" method)
                :status-code status-name
                :details method))
        ;; UNAVAILABLE → rpc-unavailable (retryable by with-retry)
        ((= status-code +grpc-status-unavailable+)
         (error 'rpc-unavailable
                :message (format nil "~A: service unavailable" method)
                :status-code status-name
                :details method))
        ;; Everything else → rpc-error (not retryable)
        (t
         (error 'rpc-error
                :message (format nil "~A: ~A" method status-name)
                :status-code status-name
                :details method))))))

;;; -----------------------------------------------------------------------
;;;  Synchronous unary RPC
;;; -----------------------------------------------------------------------

(defun grpc-unary-call (channel method request-bytes &key (deadline-ms 30000) metadata)
  "Execute a synchronous unary gRPC call.

CHANNEL: grpc-channel instance
METHOD: full gRPC method path (e.g. \"/sw4rm.router.RouterService/SendMessage\")
REQUEST-BYTES: octet vector of the encoded request protobuf
DEADLINE-MS: timeout in milliseconds (default 30000)
METADATA: ignored for now (reserved for future use)

Returns: response octet vector.
Signals: rpc-timeout, rpc-unavailable, or rpc-error on failure."
  (declare (ignore metadata))
  (cond
    ((null channel)
     (error 'rpc-error
            :message "Channel is not connected"
            :status-code "UNAVAILABLE"
            :details "Call ensure-connected before invoking RPC"))
    ((not (typep channel 'grpc-channel))
     (error 'rpc-error
            :message "gRPC transport backend unavailable"
            :status-code "UNIMPLEMENTED"
            :details method))
    ((not (grpc-channel-alive-p channel))
     (error 'rpc-error
            :message "Channel is not alive"
            :status-code "UNAVAILABLE"
            :details "destroy-grpc-channel was already called")))
  (multiple-value-bind (response-bytes status-code)
      (%grpc-unary-call-raw
       (grpc-channel-raw channel)
       (grpc-channel-cq channel)
       method
       request-bytes
       deadline-ms)
    (signal-grpc-status status-code method)
    response-bytes))

;;; -----------------------------------------------------------------------
;;;  Server-streaming RPC
;;; -----------------------------------------------------------------------

(defclass stream-handle ()
  ((call-ptr
    :initarg :call-ptr
    :accessor stream-handle-call
    :documentation "Pointer to grpc_call*.")
   (thread
    :initarg :thread
    :accessor stream-handle-thread
    :documentation "Bordeaux-threads thread running the recv loop.")
   (cancelled-p
    :initform nil
    :accessor stream-handle-cancelled-p
    :documentation "T after cancel-stream is called."))
  (:documentation "Handle for an active server-streaming RPC."))

(defun cancel-stream (handle)
  "Cancel an active server stream.  Idempotent."
  (unless (stream-handle-cancelled-p handle)
    (setf (stream-handle-cancelled-p handle) t)
    (let ((call (stream-handle-call handle)))
      (unless (cffi:null-pointer-p call)
        (%grpc-call-cancel call (cffi:null-pointer))))))

(defun grpc-server-stream (channel method request-bytes callback
                           &key (deadline-ms 0))
  "Start a server-streaming RPC.

CHANNEL: grpc-channel instance
METHOD: full gRPC method path
REQUEST-BYTES: encoded request protobuf
CALLBACK: function called with each response octet vector; called with NIL on stream end
DEADLINE-MS: timeout (0 = infinite)

Returns: stream-handle that can be passed to cancel-stream."
  (ensure-grpc-available)
  (cond
    ((null channel)
     (error 'rpc-error
            :message "Channel is not connected"
            :status-code "UNAVAILABLE"
            :details "Call ensure-connected before invoking RPC"))
    ((not (typep channel 'grpc-channel))
     (error 'rpc-error
            :message "gRPC transport backend unavailable"
            :status-code "UNIMPLEMENTED"
            :details method))
    ((not (grpc-channel-alive-p channel))
     (error 'rpc-error
            :message "Channel is not alive"
            :status-code "UNAVAILABLE"
            :details "Channel not connected")))

  (let* ((raw-ch (grpc-channel-raw channel))
         (cq (grpc-cq-create))  ;; separate CQ for the stream
         (method-slice (%make-method-slice method))
         (deadline (if (and deadline-ms (> deadline-ms 0))
                       (gpr-deadline-from-ms deadline-ms)
                       (gpr-inf-future)))
         (call (%grpc-channel-create-call
                raw-ch (cffi:null-pointer) 0 cq
                method-slice (cffi:null-pointer) deadline (cffi:null-pointer)))
         (request-bb (bytes-to-grpc-byte-buffer request-bytes)))

    (when (cffi:null-pointer-p call)
      (%grpc-slice-unref method-slice)
      (grpc-byte-buffer-destroy request-bb)
      (grpc-cq-destroy cq)
      (error 'rpc-error
             :message "Failed to create streaming call"
             :status-code "INTERNAL" :details method))

    ;; Send initial metadata + request + half-close (3 ops)
    (let ((ops-size (* 3 +grpc-op-size+)))
      (cffi:with-foreign-objects ((ops :uint8 ops-size))
        (dotimes (i ops-size)
          (setf (cffi:mem-aref ops :uint8 i) 0))

        ;; Op 0: SEND_INITIAL_METADATA
        (setf (cffi:mem-ref ops :int32 0) +grpc-op-send-initial-metadata+)

        ;; Op 1: SEND_MESSAGE
        (let ((op1 (cffi:inc-pointer ops +grpc-op-size+)))
          (setf (cffi:mem-ref op1 :int32 0) +grpc-op-send-message+)
          (setf (cffi:mem-ref op1 :pointer +grpc-op-data-offset+) request-bb))

        ;; Op 2: SEND_CLOSE_FROM_CLIENT
        (let ((op2 (cffi:inc-pointer ops (* 2 +grpc-op-size+))))
          (setf (cffi:mem-ref op2 :int32 0) +grpc-op-send-close-from-client+))

        (let ((err (%grpc-call-start-batch
                    call ops 3 (cffi:null-pointer) (cffi:null-pointer))))
          (unless (zerop err)
            (%grpc-call-unref call)
            (%grpc-slice-unref method-slice)
            (grpc-byte-buffer-destroy request-bb)
            (grpc-cq-destroy cq)
            (error 'rpc-error
                   :message "Stream send batch failed"
                   :status-code "INTERNAL" :details method)))

        ;; Wait for send to complete
        (%grpc-cq-next cq (gpr-inf-future) (cffi:null-pointer))))

    (%grpc-slice-unref method-slice)
    (%grpc-byte-buffer-destroy request-bb)

    ;; Create handle and spawn recv loop thread
    (let ((handle (make-instance 'stream-handle :call-ptr call)))
      (setf (stream-handle-thread handle)
            (bordeaux-threads:make-thread
             (lambda ()
               (unwind-protect
                    (%stream-recv-loop call cq callback handle)
                 (%grpc-call-unref call)
                 (grpc-cq-destroy cq)))
             :name (format nil "grpc-stream:~A" method)))
      handle)))

(defun %stream-recv-loop (call cq callback handle)
  "Internal: repeatedly issue RECV_MESSAGE ops until stream ends or cancelled."
  (loop
    (when (stream-handle-cancelled-p handle)
      (funcall callback nil)
      (return))

    (cffi:with-foreign-objects ((ops :uint8 +grpc-op-size+)
                                (recv-msg :pointer))
      (dotimes (i +grpc-op-size+)
        (setf (cffi:mem-aref ops :uint8 i) 0))
      (setf (cffi:mem-ref recv-msg :pointer) (cffi:null-pointer))

      ;; RECV_MESSAGE op
      (setf (cffi:mem-ref ops :int32 0) +grpc-op-recv-message+)
      (setf (cffi:mem-ref ops :pointer +grpc-op-data-offset+) recv-msg)

      (let ((err (%grpc-call-start-batch
                  call ops 1 (cffi:null-pointer) (cffi:null-pointer))))
        (unless (zerop err)
          (funcall callback nil)
          (return)))

      ;; Wait for the message
      (let ((event (%grpc-cq-next cq (gpr-inf-future) (cffi:null-pointer))))
        (let ((event-type (cffi:foreign-slot-value event '(:struct grpc-event) 'type)))
          (when (= event-type +grpc-queue-shutdown+)
            (funcall callback nil)
            (return))))

      ;; Check received message
      (let ((bb (cffi:mem-ref recv-msg :pointer)))
        (if (cffi:null-pointer-p bb)
            ;; NULL means stream ended
            (progn (funcall callback nil)
                   (return))
            ;; Extract bytes and call back
            (let ((bytes (grpc-byte-buffer-to-bytes bb)))
              (%grpc-byte-buffer-destroy bb)
              (funcall callback bytes)))))))
