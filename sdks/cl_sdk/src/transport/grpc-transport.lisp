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
   (lock :initform (bordeaux-threads:make-lock "grpc-channel") :reader grpc-channel-lock)
   (calls :initform nil :accessor grpc-channel-calls)
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

Pass :tls with root-certificate contents, a path string, or T for defaults.
Construction is ownership-safe: if completion-queue creation or the wrapper
instance signals, the already-created native channel, credentials, and queue
are released before the condition propagates."
  (ensure-grpc-available)
  (grpc-init)
  (let ((grpc-target (%normalize-grpc-target target))
        (cq nil)
        (wrapper nil))
    (let* ((created (multiple-value-list
                     (if tls
                         (grpc-channel-create grpc-target :tls tls)
                         (grpc-channel-create grpc-target))))
           (channel (pop created))
           (credentials (pop created)))
      (unwind-protect
           (progn
             (setf cq (grpc-cq-create))
             (setf wrapper (make-instance 'grpc-channel
                                          :raw-channel channel
                                          :credentials credentials
                                          :completion-queue cq
                                          :target target))
             wrapper)
        ;; Once WRAPPER exists it owns the native resources; before that, any
        ;; failure path must release them here.
        (unless wrapper
          (when cq
            (grpc-cq-destroy cq))
          (when (and channel (not (cffi:null-pointer-p channel)))
            (grpc-channel-destroy channel))
          (when (and credentials (not (cffi:null-pointer-p credentials)))
            (%grpc-channel-credentials-release credentials)))))))

(defstruct grpc-call-resource channel pointer queue)

(defun %make-grpc-call-resource (channel method deadline-ms)
  "Register the native call before a stream is returned or a channel can close."
  (bordeaux-threads:with-lock-held ((grpc-channel-lock channel))
    (unless (grpc-channel-alive-p channel)
      (error 'rpc-unavailable :message "Channel is closed" :status-code "UNAVAILABLE" :details method))
    (grpc-init) ; The call keeps the C runtime alive independently of its channel.
    (let ((cq (grpc-cq-create)) (success nil))
      (unwind-protect
           (let* ((slice (%make-method-slice method))
                  (deadline (if (and deadline-ms (plusp deadline-ms))
                                (gpr-deadline-from-ms deadline-ms) (gpr-inf-future)))
                  (call (unwind-protect
                            (%grpc-channel-create-call (grpc-channel-raw channel)
                             (cffi:null-pointer) 0 cq slice (cffi:null-pointer)
                             deadline (cffi:null-pointer))
                          (%grpc-slice-unref slice))))
             (when (cffi:null-pointer-p call)
               (error 'rpc-error :message "Cannot create native call"
                      :status-code "INTERNAL" :details method))
             (let ((resource (make-grpc-call-resource :channel channel :pointer call :queue cq)))
               (push resource (grpc-channel-calls channel))
               (setf success t)
               resource))
        (unless success (grpc-cq-destroy cq) (grpc-shutdown))))))

(defun %release-grpc-call-resource (resource)
  (let ((channel (grpc-call-resource-channel resource))
        (call (grpc-call-resource-pointer resource)))
    (bordeaux-threads:with-lock-held ((grpc-channel-lock channel))
      (setf (grpc-channel-calls channel) (delete resource (grpc-channel-calls channel)))
      (%grpc-call-cancel call (cffi:null-pointer))
      (%grpc-call-unref call))
    (grpc-cq-destroy (grpc-call-resource-queue resource))
    (grpc-shutdown)))

(defun destroy-grpc-channel (channel)
  "Close the channel and cancel active calls. Their workers own final cleanup."
  (when (typep channel 'grpc-channel)
    (bordeaux-threads:with-lock-held ((grpc-channel-lock channel))
      (when (grpc-channel-alive-p channel)
        (setf (grpc-channel-alive-p channel) nil)
        (dolist (resource (grpc-channel-calls channel))
          (%grpc-call-cancel (grpc-call-resource-pointer resource) (cffi:null-pointer)))
        (grpc-cq-destroy (grpc-channel-cq channel))
        (grpc-channel-destroy (grpc-channel-raw channel))
        (when (grpc-channel-credentials channel)
          (%grpc-channel-credentials-release (grpc-channel-credentials channel))
          (setf (grpc-channel-credentials channel) nil))
        (grpc-shutdown)))))

;;; -----------------------------------------------------------------------
;;;  Status → condition mapping
;;; -----------------------------------------------------------------------

(defun signal-grpc-status (status-code method &optional details)
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
                :details (or details method)))
        ;; UNAVAILABLE → rpc-unavailable (retryable by with-retry)
        ((= status-code +grpc-status-unavailable+)
         (error 'rpc-unavailable
                :message (format nil "~A: service unavailable" method)
                :status-code status-name
                :details (or details method)))
        ;; Everything else → rpc-error (not retryable)
        (t
         (error 'rpc-error
                :message (format nil "~A: ~A" method status-name)
                :status-code status-name
                :details (or details method)))))))

;;; -----------------------------------------------------------------------
;;;  Synchronous unary RPC
;;; -----------------------------------------------------------------------

(defun grpc-unary-call (channel method request-bytes &key (deadline-ms 30000) metadata)
  "Execute a synchronous unary gRPC call.

CHANNEL: grpc-channel instance
METHOD: full gRPC method path (e.g. \"/sw4rm.router.RouterService/SendMessage\")
REQUEST-BYTES: octet vector of the encoded request protobuf
DEADLINE-MS: timeout in milliseconds (default 30000)
METADATA: alist of string keys and string or octet-vector values

Returns: response octet vector.
Signals: rpc-timeout, rpc-unavailable, or rpc-error on failure."
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
  (let ((resource (%make-grpc-call-resource channel method deadline-ms)))
    (unwind-protect
         (multiple-value-bind (response-bytes status-code details)
             (%grpc-unary-call-raw (grpc-call-resource-pointer resource)
                                  (grpc-call-resource-queue resource) request-bytes metadata)
           (signal-grpc-status status-code method details)
           response-bytes)
      (%release-grpc-call-resource resource))))

;;; -----------------------------------------------------------------------
;;;  Server-streaming RPC
;;; -----------------------------------------------------------------------

(defclass stream-handle ()
  ((call-ptr :initarg :call-ptr :initform (cffi:null-pointer) :accessor stream-handle-call)
   (thread :initarg :thread :initform nil :accessor stream-handle-thread)
   (lock :initform (bordeaux-threads:make-lock "grpc-stream") :reader stream-handle-lock)
   (cancelled-p :initform nil :accessor stream-handle-cancelled-p)
   (error :initform nil :accessor stream-handle-error))
  (:documentation "A cancellable stream. WAIT-FOR-STREAM joins and reports remote errors."))

(defun cancel-stream (handle)
  "Cancel a stream safely, including before its worker starts and after EOF."
  (bordeaux-threads:with-lock-held ((stream-handle-lock handle))
    (unless (stream-handle-cancelled-p handle)
      (setf (stream-handle-cancelled-p handle) t)
      (unless (cffi:null-pointer-p (stream-handle-call handle))
        (%grpc-call-cancel (stream-handle-call handle) (cffi:null-pointer)))))
  handle)

(defun wait-for-stream (handle)
  "Wait for stream termination; signal any remote status or callback error.
Explicit cancellation produces the remote CANCELLED condition."
  (bordeaux-threads:join-thread (stream-handle-thread handle))
  (when (stream-handle-error handle) (error (stream-handle-error handle)))
  handle)

(defun %stream-worker-body (resource method request-bytes metadata callback handle)
  "Worker thread body for GRPC-SERVER-STREAM.

Runs the stream to completion, then notifies the consumer with NIL only on
graceful end-of-stream (R20).  Error paths are recorded on HANDLE and
surface through WAIT-FOR-STREAM instead of a spurious EOF callback.
Owns and releases RESOURCE."
  (unwind-protect
       (handler-case
           (progn
             (%grpc-stream-call resource method request-bytes metadata callback)
             (handler-case (funcall callback nil)
               (error (condition)
                 (unless (stream-handle-error handle)
                   (setf (stream-handle-error handle) condition)))))
         (error (condition)
           (setf (stream-handle-error handle) condition)))
    (bordeaux-threads:with-lock-held ((stream-handle-lock handle))
      (setf (stream-handle-call handle) (cffi:null-pointer)))
    (%release-grpc-call-resource resource)))

(defun grpc-server-stream (channel method request-bytes callback
                           &key (deadline-ms 0) metadata)
  "Start a server stream and return immediately with a cancellable handle.
CALLBACK receives octets, then NIL once, only on graceful end-of-stream.
Error paths are recorded on the handle and surface via WAIT-FOR-STREAM.
METADATA is an alist; DEADLINE-MS zero means no deadline."
  (ensure-grpc-available)
  (unless (and (typep channel 'grpc-channel) (grpc-channel-alive-p channel))
    (error 'rpc-unavailable :message "Channel is not connected"
           :status-code "UNAVAILABLE" :details method))
  (let* ((resource (%make-grpc-call-resource channel method deadline-ms))
         (handle (make-instance 'stream-handle :call-ptr (grpc-call-resource-pointer resource))))
    (handler-case
        (setf (stream-handle-thread handle)
              (bordeaux-threads:make-thread
               (lambda ()
                 (%stream-worker-body resource method request-bytes metadata callback handle))
               :name (format nil "grpc-stream:~A" method)))
      (error (condition) (%release-grpc-call-resource resource) (error condition)))
    handle))

(defun %grpc-stream-call (resource method request-bytes metadata callback)
  (let ((cq (grpc-call-resource-queue resource))
        (call (grpc-call-resource-pointer resource))
        (request-bb (bytes-to-grpc-byte-buffer request-bytes)))
    (unwind-protect
         (%call-with-grpc-metadata
          metadata
          (lambda (entries count)
            (cffi:with-foreign-objects ((ops :uint8 (* 4 +grpc-op-size+))
                                       (initial '(:struct grpc-metadata-array))
                                       (trailing '(:struct grpc-metadata-array))
                                       (message :pointer) (status :int32)
                                       (details '(:struct grpc-slice)))
              (%zero-foreign ops (* 4 +grpc-op-size+))
              (%zero-foreign details (cffi:foreign-type-size '(:struct grpc-slice)))
              (%grpc-metadata-array-init initial)
              (%grpc-metadata-array-init trailing)
              (setf (cffi:mem-ref message :pointer) (cffi:null-pointer)
                    (cffi:mem-ref status :int32) +grpc-status-unknown+)
              (unwind-protect
                   (progn
                     (%set-send-metadata ops 0 entries count)
                     (%set-grpc-op ops 1 +grpc-op-send-message+ request-bb)
                     (%set-grpc-op ops 2 +grpc-op-send-close-from-client+)
                     (%set-grpc-op ops 3 +grpc-op-recv-initial-metadata+ initial)
                     (%run-grpc-batch call cq ops 4)
                     (loop
                       (%zero-foreign ops +grpc-op-size+)
                       (%set-grpc-op ops 0 +grpc-op-recv-message+ message)
                       (%run-grpc-batch call cq ops 1)
                       (let ((bb (cffi:mem-ref message :pointer)))
                         (when (cffi:null-pointer-p bb) (return))
                         (let ((bytes (unwind-protect (grpc-byte-buffer-to-bytes bb)
                                        (grpc-byte-buffer-destroy bb)
                                        (setf (cffi:mem-ref message :pointer) (cffi:null-pointer)))))
                           (funcall callback bytes))))
                     (%zero-foreign ops +grpc-op-size+)
                     (%set-grpc-op ops 0 +grpc-op-recv-status-on-client+ trailing status details)
                     (%run-grpc-batch call cq ops 1)
                     (signal-grpc-status
                      (cffi:mem-ref status :int32) method
                      (babel:octets-to-string (grpc-slice-to-bytes details) :encoding :utf-8)))
                (grpc-byte-buffer-destroy (cffi:mem-ref message :pointer))
                (%grpc-slice-unref (cffi:mem-ref details '(:struct grpc-slice)))
                (%grpc-metadata-array-destroy initial)
                (%grpc-metadata-array-destroy trailing)))))
      (grpc-byte-buffer-destroy request-bb))))
