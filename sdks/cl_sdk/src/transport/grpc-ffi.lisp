;;;; grpc-ffi.lisp — Raw CFFI bindings to libgrpc C core
;;;;
;;;; Minimal C API surface for unary and server-streaming RPCs.
;;;; Gracefully degrades when libgrpc.so is not installed.

(in-package #:sw4rm-sdk)

(define-condition grpc-call-error (error)
  ((call-function
    :initarg :call-function
    :reader grpc-call-error-function
    :documentation "The libgrpc C function that failed.")
   (call-status
    :initarg :call-status
    :reader grpc-call-error-status
    :documentation "The C-level error code (not a gRPC wire status)."))
  (:report (lambda (condition stream)
             (format stream "libgrpc call error in ~A (C error code ~D)"
                     (grpc-call-error-function condition)
                     (grpc-call-error-status condition))))
  (:documentation "A libgrpc C-API invocation failed.

This is distinct from RPC-ERROR: the wire status codes reported there come
from the remote service, while GRPC-CALL-ERROR means the local C call itself
was rejected before anything reached the network."))

;;; -----------------------------------------------------------------------
;;;  Library availability
;;; -----------------------------------------------------------------------

(defvar *grpc-available* nil
  "T when libgrpc was successfully loaded; NIL otherwise.")

(cffi:define-foreign-library libgrpc
  (:unix (:or "libgrpc.so" "libgrpc.so.29"))
  (t (:default "libgrpc")))

(handler-case
    (progn
      (cffi:use-foreign-library libgrpc)
      (setf *grpc-available* t))
  (cffi:load-foreign-library-error (e)
    (warn "libgrpc not found: ~A~%gRPC transport will not be available." e)
    (setf *grpc-available* nil)))

(defun ensure-grpc-available ()
  "Signal rpc-error if libgrpc was not loaded."
  (unless *grpc-available*
    (error 'rpc-error
           :message "libgrpc.so not loaded — install grpc >= 1.50"
           :status-code "UNAVAILABLE"
           :details "CFFI library load failed")))

;;; -----------------------------------------------------------------------
;;;  Constants
;;; -----------------------------------------------------------------------

;; grpc_op_type enum
(defconstant +grpc-op-send-initial-metadata+    0)
(defconstant +grpc-op-send-message+             1)
(defconstant +grpc-op-send-close-from-client+   2)
(defconstant +grpc-op-send-status-from-server+  3)
(defconstant +grpc-op-recv-initial-metadata+    4)
(defconstant +grpc-op-recv-message+             5)
(defconstant +grpc-op-recv-status-on-client+    6)
(defconstant +grpc-op-recv-close-on-server+     7)

;; grpc_status_code
(defconstant +grpc-status-ok+                  0)
(defconstant +grpc-status-cancelled+           1)
(defconstant +grpc-status-unknown+             2)
(defconstant +grpc-status-invalid-argument+    3)
(defconstant +grpc-status-deadline-exceeded+   4)
(defconstant +grpc-status-not-found+           5)
(defconstant +grpc-status-already-exists+      6)
(defconstant +grpc-status-permission-denied+   7)
(defconstant +grpc-status-unauthenticated+    16)
(defconstant +grpc-status-resource-exhausted+  8)
(defconstant +grpc-status-failed-precondition+ 9)
(defconstant +grpc-status-aborted+            10)
(defconstant +grpc-status-out-of-range+       11)
(defconstant +grpc-status-unimplemented+      12)
(defconstant +grpc-status-internal+           13)
(defconstant +grpc-status-unavailable+        14)
(defconstant +grpc-status-data-loss+          15)

;; grpc_completion_type enum
(defconstant +grpc-queue-shutdown+   0)
(defconstant +grpc-queue-timeout+    1)
(defconstant +grpc-op-complete+      2)

;; GPR clock type
(defconstant +gpr-clock-monotonic+  0)
(defconstant +gpr-clock-realtime+   1)
(defconstant +gpr-clock-precise+    2)
(defconstant +gpr-timespan+         3)

;;; -----------------------------------------------------------------------
;;;  Struct definitions (opaque/flat)
;;; -----------------------------------------------------------------------

;; gpr_timespec — 16 bytes: int64 tv_sec, int32 tv_nsec, int32 clock_type
(cffi:defcstruct gpr-timespec
  (tv-sec  :int64)
  (tv-nsec :int32)
  (clock-type :int32))

;; grpc_metadata_array — holds pointer, count, capacity
(cffi:defcstruct grpc-metadata-array
  (count    :size)
  (capacity :size)
  (metadata :pointer))

;; grpc_event — completion queue event
(cffi:defcstruct grpc-event
  (type    :int32)    ;; grpc_completion_type
  (success :int32)    ;; bool
  (tag     :pointer))

;; gRPC 1.51 C ABI: pointer followed by an aligned, 24-byte data union.
;; Scalar words avoid CFFI's unsupported array-member translation by value.
(cffi:defcstruct grpc-slice
  (refcount :pointer)
  (data-0 :uint64)
  (data-1 :uint64)
  (data-2 :uint64))

(cffi:defcstruct grpc-metadata
  (key (:struct grpc-slice))
  (value (:struct grpc-slice))
  (internal-data :pointer :count 4))

;; grpc_byte_buffer_reader
(cffi:defcstruct grpc-byte-buffer-reader
  (buffer-in  :pointer)
  (buffer-out :pointer)
  (current    :uint32))

(cffi:defcstruct grpc-ssl-pem-key-cert-pair
  (private-key :string)
  (cert-chain :string))

;; The union reserves EIGHT pointers, including members unused by this client.
;; grpc_types.h therefore specifies an 80-byte grpc_op on 64-bit platforms.
(cffi:defcstruct grpc-op
  (op :int32)
  (flags :uint32)
  (reserved :pointer)
  (data :pointer :count 8))
(defconstant +grpc-op-size+ 80)
(defconstant +grpc-op-data-offset+ 16)

;;; -----------------------------------------------------------------------
;;;  Lifecycle
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_init" %grpc-init) :void)
(cffi:defcfun ("grpc_shutdown" %grpc-shutdown) :void)

(defun grpc-init ()
  "Initialize the gRPC library. Safe to call multiple times."
  (ensure-grpc-available)
  (%grpc-init))

(defun grpc-shutdown ()
  "Shut down the gRPC library."
  (ensure-grpc-available)
  (%grpc-shutdown))

;;; -----------------------------------------------------------------------
;;;  Channel
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_insecure_credentials_create" %grpc-insecure-credentials-create)
    :pointer)

(cffi:defcfun ("grpc_channel_create" %grpc-channel-create)
    :pointer
  (target :string)
  (credentials :pointer)
  (args :pointer))

(cffi:defcfun ("grpc_ssl_credentials_create" %grpc-ssl-credentials-create)
    :pointer
  (pem-root-certs :string)
  (pem-key-cert-pair :pointer)
  (reserved :pointer))

(cffi:defcfun ("grpc_channel_credentials_release" %grpc-channel-credentials-release)
    :void
  (credentials :pointer))

(cffi:defcfun ("grpc_ssl_channel_create" %grpc-ssl-channel-create)
    :pointer
  (credentials :pointer)
  (target :string)
  (args   :pointer)
  (reserved :pointer))

(cffi:defcfun ("grpc_secure_channel_create" %grpc-secure-channel-create)
    :pointer
  (credentials :pointer)
  (target :string)
  (args   :pointer)
  (reserved :pointer))

(cffi:defcfun ("grpc_channel_destroy" %grpc-channel-destroy) :void
  (channel :pointer))

(cffi:defcfun ("grpc_channel_check_connectivity_state" %grpc-channel-check-connectivity-state)
    :int32
  (channel :pointer)
  (try-to-connect :int32))

(defun grpc-channel-create-supported-p ()
  "True if the runtime provides the current channel constructor."
  (not (null (ignore-errors (cffi:foreign-symbol-pointer "grpc_channel_create")))))

(defun grpc-channel-create-secure-fn ()
  "Return a compatibility wrapper around the current channel constructor."
  (when (grpc-channel-create-supported-p)
    (lambda (credentials target args reserved)
      (declare (ignore reserved))
      (%grpc-channel-create target credentials args))))

(defun grpc-channel-tls-root-certs (tls)
  "Normalize TLS input into PEM text suitable for grpc_ssl_credentials_create.

If TLS is T, NIL is returned to use system default roots.
If TLS is a pathname or path string, file contents are read.
Otherwise, TLS must be a PEM string."
  (cond
    ((eq tls t) nil)
    ((null tls) nil)
    ((pathnamep tls)
     (with-open-file (stream tls :direction :input :external-format :utf-8)
       (let ((contents (make-string (file-length stream))))
         (read-sequence contents stream)
         contents)))
    ((and (stringp tls)
          (> (length tls) 0)
          (probe-file tls))
     (with-open-file (stream tls :direction :input :external-format :utf-8)
       (let ((contents (make-string (file-length stream))))
         (read-sequence contents stream)
         contents)))
    ((stringp tls) tls)
    (t (error "Invalid :tls value for make-grpc-channel: ~S" tls))))

(defun grpc-channel-create (target &key tls)
  "Create a gRPC channel to TARGET.

When TLS is NIL, creates an insecure channel.
When TLS is truthy, creates a secure channel using the supplied root certificate
string, returning CHANNEL and CREDENTIALS as two values.
"
  (ensure-grpc-available)
  (unless (= (cffi:foreign-type-size :pointer) 8)
    (error "The native gRPC bindings currently require a 64-bit platform."))
  (if (not tls)
      (let ((credentials (%grpc-insecure-credentials-create)))
        (unwind-protect
             (let ((channel (%grpc-channel-create target credentials (cffi:null-pointer))))
               (if (cffi:null-pointer-p channel)
                   (error "Insecure channel creation failed: channel creation returned NULL")
                   (values channel nil)))
          (%grpc-channel-credentials-release credentials)))
      (let ((root-certs (grpc-channel-tls-root-certs tls))
            (creator (grpc-channel-create-secure-fn))
            (credentials nil))
        (unless creator
          (error "TLS channel support is unavailable: grpc_channel_create was not found."))
        (setf credentials (%grpc-ssl-credentials-create root-certs (cffi:null-pointer)
                                                       (cffi:null-pointer)))
        (when (or (null credentials) (cffi:null-pointer-p credentials))
          (error "TLS channel creation failed: credentials creation returned NULL"))
        (let ((channel (funcall creator credentials target (cffi:null-pointer)
                               (cffi:null-pointer))))
          (if (or (null channel) (cffi:null-pointer-p channel))
              (progn
                (%grpc-channel-credentials-release credentials)
                (error "TLS channel creation failed: channel creation returned NULL"))
              (values channel credentials))))))

(defun grpc-channel-destroy (channel)
  "Destroy a gRPC channel."
  (ensure-grpc-available)
  (%grpc-channel-destroy channel))

(defun grpc-channel-connectivity-state (channel &optional (try-connect nil))
  "Get channel connectivity state. Returns integer enum."
  (%grpc-channel-check-connectivity-state channel (if try-connect 1 0)))

;;; -----------------------------------------------------------------------
;;;  Completion Queue
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_completion_queue_create_for_next" %grpc-cq-create-for-next)
    :pointer
  (reserved :pointer))

(cffi:defcfun ("grpc_completion_queue_next" %grpc-cq-next)
    (:struct grpc-event)
  (cq :pointer)
  (deadline (:struct gpr-timespec))
  (reserved :pointer))

(cffi:defcfun ("grpc_completion_queue_shutdown" %grpc-cq-shutdown) :void
  (cq :pointer))

(cffi:defcfun ("grpc_completion_queue_destroy" %grpc-cq-destroy) :void
  (cq :pointer))

(defun grpc-cq-create ()
  "Create a new completion queue for next-style polling."
  (ensure-grpc-available)
  (%grpc-cq-create-for-next (cffi:null-pointer)))

(defun grpc-cq-destroy (cq)
  "Shut down, drain, and destroy a completion queue with no pending batches."
  (%grpc-cq-shutdown cq)
  (loop until (= (getf (%grpc-cq-next cq (gpr-inf-future) (cffi:null-pointer)) 'type)
                 +grpc-queue-shutdown+))
  (%grpc-cq-destroy cq))

;;; -----------------------------------------------------------------------
;;;  Time helpers
;;; -----------------------------------------------------------------------

(cffi:defcfun ("gpr_time_from_millis" %gpr-time-from-millis)
    (:struct gpr-timespec)
  (ms :int64)
  (clock-type :int32))

(cffi:defcfun ("gpr_inf_future" %gpr-inf-future)
    (:struct gpr-timespec)
  (clock-type :int32))

(cffi:defcfun ("gpr_now" %gpr-now) (:struct gpr-timespec)
  (clock-type :int32))

(cffi:defcfun ("gpr_time_add" %gpr-time-add) (:struct gpr-timespec)
  (time (:struct gpr-timespec))
  (span (:struct gpr-timespec)))

(defun gpr-deadline-from-ms (ms)
  "Create a deadline timespec MS milliseconds from now (using REALTIME clock)."
  (%gpr-time-add (%gpr-now +gpr-clock-realtime+)
                 (%gpr-time-from-millis ms +gpr-timespan+)))

(defun gpr-inf-future ()
  "Return an infinite-future timespec (block forever)."
  (%gpr-inf-future +gpr-clock-realtime+))

;;; -----------------------------------------------------------------------
;;;  Slice & byte buffer
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_slice_from_copied_buffer" %grpc-slice-from-copied-buffer)
    (:struct grpc-slice)
  (source :pointer)
  (len    :size))

(cffi:defcfun ("grpc_slice_unref" %grpc-slice-unref) :void
  (slice (:struct grpc-slice)))

(cffi:defcfun ("grpc_raw_byte_buffer_create" %grpc-raw-byte-buffer-create)
    :pointer   ;; grpc_byte_buffer*
  (slices :pointer)       ;; grpc_slice*
  (nslices :size))

(cffi:defcfun ("grpc_byte_buffer_destroy" %grpc-byte-buffer-destroy) :void
  (bb :pointer))

(cffi:defcfun ("grpc_byte_buffer_reader_init" %grpc-bb-reader-init) :int32
  (reader :pointer)
  (buffer :pointer))

(cffi:defcfun ("grpc_byte_buffer_reader_next" %grpc-bb-reader-next) :int32
  (reader :pointer)
  (slice  :pointer))

(cffi:defcfun ("grpc_byte_buffer_reader_destroy" %grpc-bb-reader-destroy) :void
  (reader :pointer))

(defun bytes-to-grpc-byte-buffer (octets)
  "Convert a CL octet vector to a grpc_byte_buffer*. Caller must destroy."
  (let ((len (length octets)))
    (cffi:with-foreign-object (src :uint8 (max len 1))
      (loop for i below len do
        (setf (cffi:mem-aref src :uint8 i) (aref octets i)))
      (cffi:with-foreign-object (slice-mem '(:struct grpc-slice))
        (let ((slice (%grpc-slice-from-copied-buffer src len)))
          ;; Copy slice struct into foreign memory for grpc_raw_byte_buffer_create
          (setf (cffi:mem-ref slice-mem '(:struct grpc-slice)) slice)
          (let ((bb (%grpc-raw-byte-buffer-create slice-mem 1)))
            (%grpc-slice-unref slice)
            bb))))))

(defun grpc-slice-to-bytes (slice-pointer)
  "Copy a gRPC slice using the public grpc_slice layout."
  (let* ((inline-p (cffi:null-pointer-p (cffi:mem-ref slice-pointer :pointer)))
         (length (if inline-p (cffi:mem-ref slice-pointer :uint8 8)
                     (cffi:mem-ref slice-pointer :size 8)))
         (data (if inline-p (cffi:inc-pointer slice-pointer 9)
                   (cffi:mem-ref slice-pointer :pointer 16)))
         (bytes (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (i length bytes) (setf (aref bytes i) (cffi:mem-aref data :uint8 i)))))

(defun grpc-byte-buffer-to-bytes (bb)
  "Copy all slices and release each reference acquired by the reader."
  (when (cffi:null-pointer-p bb)
    (return-from grpc-byte-buffer-to-bytes (make-array 0 :element-type '(unsigned-byte 8))))
  (cffi:with-foreign-object (reader '(:struct grpc-byte-buffer-reader))
    (when (zerop (%grpc-bb-reader-init reader bb))
      (error 'rpc-error :message "Cannot initialize byte buffer reader"
             :status-code "INTERNAL" :details "grpc_byte_buffer_reader_init"))
    (unwind-protect
         (let ((parts nil))
           (cffi:with-foreign-object (slice '(:struct grpc-slice))
             (loop while (plusp (%grpc-bb-reader-next reader slice)) do
               (unwind-protect (push (grpc-slice-to-bytes slice) parts)
                 (%grpc-slice-unref (cffi:mem-ref slice '(:struct grpc-slice))))))
           (apply #'concatenate '(simple-array (unsigned-byte 8) (*)) (nreverse parts)))
      (%grpc-bb-reader-destroy reader))))

;;; -----------------------------------------------------------------------
;;;  Call
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_channel_create_call" %grpc-channel-create-call)
    :pointer   ;; grpc_call*
  (channel       :pointer)
  (parent-call   :pointer)
  (propagation   :uint32)
  (cq            :pointer)
  (method        (:struct grpc-slice))
  (host          :pointer)  ;; grpc_slice* or NULL
  (deadline      (:struct gpr-timespec))
  (reserved      :pointer))

(cffi:defcfun ("grpc_call_start_batch" %grpc-call-start-batch) :int32
  (call     :pointer)
  (ops      :pointer)
  (nops     :size)
  (tag      :pointer)
  (reserved :pointer))

(cffi:defcfun ("grpc_call_unref" %grpc-call-unref) :void
  (call :pointer))

(cffi:defcfun ("grpc_call_cancel" %grpc-call-cancel) :int32
  (call     :pointer)
  (reserved :pointer))

;;; -----------------------------------------------------------------------
;;;  Metadata array init/destroy
;;; -----------------------------------------------------------------------

(cffi:defcfun ("grpc_metadata_array_init" %grpc-metadata-array-init) :void
  (array :pointer))

(cffi:defcfun ("grpc_metadata_array_destroy" %grpc-metadata-array-destroy) :void
  (array :pointer))

;;; -----------------------------------------------------------------------
;;;  High-level unary call helper (builds 6 ops)
;;; -----------------------------------------------------------------------

(defun %make-method-slice (method-string)
  "Create a grpc_slice from a method path string (e.g. \"/sw4rm.router.RouterService/SendMessage\")."
  (cffi:with-foreign-string (cstr method-string)
    (%grpc-slice-from-copied-buffer cstr (length method-string))))

(defun %zero-foreign (pointer size)
  (dotimes (i size) (setf (cffi:mem-aref pointer :uint8 i) 0)))

(defun %set-grpc-op (ops index kind &rest pointers)
  (let ((op (cffi:inc-pointer ops (* index +grpc-op-size+))))
    (setf (cffi:mem-ref op :int32) kind)
    (loop for pointer in pointers for offset from +grpc-op-data-offset+ by 8 do
      (setf (cffi:mem-ref op :pointer offset) pointer))))

(defun %run-grpc-batch (call cq ops count)
  "Wait for this call's batch on its dedicated queue; return completion success."
  (let ((status (%grpc-call-start-batch call ops count (cffi:null-pointer) (cffi:null-pointer))))
    (unless (zerop status)
      (error 'grpc-call-error :call-function 'grpc_call_start_batch :call-status status)))
  (let ((event (%grpc-cq-next cq (gpr-inf-future) (cffi:null-pointer))))
    (unless (= (getf event 'type) +grpc-op-complete+)
      (error 'grpc-call-error :call-function 'grpc_completion_queue_next
             :call-status (getf event 'type)))
    (not (zerop (getf event 'success)))))

(defun %call-with-grpc-metadata (metadata function)
  "Keep metadata slices alive through the send batch. METADATA is an alist."
  (cffi:with-foreign-object (entries '(:struct grpc-metadata) (max 1 (length metadata)))
    (let ((slices nil))
      (unwind-protect
           (progn
             (loop for (key . value) in metadata for index from 0 do
               (unless (and (stringp key) (or (stringp value) (typep value '(vector (unsigned-byte 8)))))
                 (error "Metadata requires string keys and string or octet-vector values"))
               (let ((entry (cffi:mem-aptr entries '(:struct grpc-metadata) index)))
                 (dolist (pair (list (cons 'key key) (cons 'value value)))
                   (let* ((bytes (if (stringp (cdr pair))
                                     (babel:string-to-octets (cdr pair) :encoding :utf-8)
                                     (cdr pair)))
                          (slice (cffi:with-pointer-to-vector-data (data bytes)
                                   (%grpc-slice-from-copied-buffer data (length bytes)))))
                     (push slice slices)
                     (setf (cffi:mem-ref
                            (cffi:foreign-slot-pointer entry '(:struct grpc-metadata) (car pair))
                            '(:struct grpc-slice)) slice)))))
             (funcall function entries (length metadata)))
        (dolist (slice slices) (%grpc-slice-unref slice))))))

(defun %set-send-metadata (ops index metadata count)
  (%set-grpc-op ops index +grpc-op-send-initial-metadata+)
  (let ((op (cffi:inc-pointer ops (* index +grpc-op-size+))))
    (setf (cffi:mem-ref op :size +grpc-op-data-offset+) count
          (cffi:mem-ref op :pointer (+ +grpc-op-data-offset+ 8)) metadata)))

(defun %grpc-unary-call-raw (call cq request-bytes metadata)
  "Exchange one unary request on a managed call and its dedicated queue."
  (let ((request-bb (bytes-to-grpc-byte-buffer request-bytes)))
    (unwind-protect
         (cffi:with-foreign-objects ((ops :uint8 (* 6 +grpc-op-size+))
                                    (initial '(:struct grpc-metadata-array))
                                    (trailing '(:struct grpc-metadata-array))
                                    (message :pointer) (status :int32)
                                    (details '(:struct grpc-slice)))
           (%zero-foreign ops (* 6 +grpc-op-size+))
           (%zero-foreign details (cffi:foreign-type-size '(:struct grpc-slice)))
           (%grpc-metadata-array-init initial)
           (%grpc-metadata-array-init trailing)
           (setf (cffi:mem-ref message :pointer) (cffi:null-pointer)
                 (cffi:mem-ref status :int32) +grpc-status-unknown+)
           (unwind-protect
                (%call-with-grpc-metadata
                 metadata
                 (lambda (entries count)
                   (%set-send-metadata ops 0 entries count)
                   (%set-grpc-op ops 1 +grpc-op-send-message+ request-bb)
                   (%set-grpc-op ops 2 +grpc-op-send-close-from-client+)
                   (%set-grpc-op ops 3 +grpc-op-recv-initial-metadata+ initial)
                   (%set-grpc-op ops 4 +grpc-op-recv-message+ message)
                   (%set-grpc-op ops 5 +grpc-op-recv-status-on-client+ trailing status details)
                   (%run-grpc-batch call cq ops 6)
                   (values (grpc-byte-buffer-to-bytes (cffi:mem-ref message :pointer))
                           (cffi:mem-ref status :int32)
                           (babel:octets-to-string (grpc-slice-to-bytes details) :encoding :utf-8))))
             (grpc-byte-buffer-destroy (cffi:mem-ref message :pointer))
             (%grpc-slice-unref (cffi:mem-ref details '(:struct grpc-slice)))
             (%grpc-metadata-array-destroy initial)
             (%grpc-metadata-array-destroy trailing)))
      (grpc-byte-buffer-destroy request-bb))))

(defun grpc-byte-buffer-destroy (bb)
  "Safe wrapper — checks for null before destroying."
  (unless (cffi:null-pointer-p bb)
    (%grpc-byte-buffer-destroy bb)))
