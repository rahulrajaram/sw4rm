;;;; grpc-ffi.lisp — Raw CFFI bindings to libgrpc C core
;;;;
;;;; Minimal C API surface for unary and server-streaming RPCs.
;;;; Gracefully degrades when libgrpc.so is not installed.

(in-package #:sw4rm-sdk)

;;; -----------------------------------------------------------------------
;;;  Library availability
;;; -----------------------------------------------------------------------

(defvar *grpc-available* nil
  "T when libgrpc was successfully loaded; NIL otherwise.")

(cffi:define-foreign-library libgrpc
  (:unix "libgrpc.so")
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

;; grpc_slice — opaque 32-byte union; we treat it as a blob
(cffi:defcstruct grpc-slice
  (blob :uint8 :count 32))

;; grpc_byte_buffer_reader
(cffi:defcstruct grpc-byte-buffer-reader
  (buffer-in  :pointer)
  (buffer-out :pointer)
  (current    :uint32)
  (pad        :uint8 :count 28))

;; grpc_op — 40-byte struct per operation
;; Due to the complex union layout, we allocate raw memory and fill
;; fields at known byte offsets.  The offsets below assume grpc >= 1.50
;; with standard System V AMD64 ABI alignment:
;;
;;   offset 0:  op (int32)
;;   offset 4:  flags (uint32)
;;   offset 8:  reserved (pointer)
;;   offset 16: data union (24 bytes)
;;   Total: 40 bytes
(defconstant +grpc-op-size+ 40)
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

(cffi:defcfun ("grpc_insecure_channel_create" %grpc-insecure-channel-create)
    :pointer   ;; grpc_channel*
  (target :string)
  (args   :pointer)     ;; grpc_channel_args* or NULL
  (reserved :pointer))

(cffi:defcfun ("grpc_channel_destroy" %grpc-channel-destroy) :void
  (channel :pointer))

(cffi:defcfun ("grpc_channel_check_connectivity_state" %grpc-channel-check-connectivity-state)
    :int32
  (channel :pointer)
  (try-to-connect :int32))

(defun grpc-channel-create (target)
  "Create an insecure gRPC channel to TARGET (e.g. \"localhost:50051\")."
  (ensure-grpc-available)
  (%grpc-insecure-channel-create target (cffi:null-pointer) (cffi:null-pointer)))

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
  "Shut down and destroy a completion queue."
  (%grpc-cq-shutdown cq)
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

(defun gpr-deadline-from-ms (ms)
  "Create a deadline timespec MS milliseconds from now (using REALTIME clock)."
  (%gpr-time-from-millis ms +gpr-clock-realtime+))

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

(defun grpc-byte-buffer-to-bytes (bb)
  "Extract octets from a grpc_byte_buffer*. Returns an octet vector."
  (when (cffi:null-pointer-p bb)
    (return-from grpc-byte-buffer-to-bytes (make-array 0 :element-type '(unsigned-byte 8))))
  (cffi:with-foreign-object (reader :uint8 64) ;; grpc_byte_buffer_reader is <64 bytes
    (when (zerop (%grpc-bb-reader-init reader bb))
      (error 'rpc-error
             :message "Failed to init byte buffer reader"
             :status-code "INTERNAL" :details "grpc_byte_buffer_reader_init returned 0"))
    (let ((result (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
      (cffi:with-foreign-object (slice-out '(:struct grpc-slice))
        (loop while (not (zerop (%grpc-bb-reader-next reader slice-out)))
              do
                 ;; Extract data pointer and length from the slice
                 ;; grpc_slice layout: first 8 bytes are refcount/inline flag,
                 ;; followed by data depending on whether it's inline or heap.
                 ;; We use GRPC_SLICE_START_PTR / GRPC_SLICE_LENGTH macros via
                 ;; grpc_slice_to_c_string alternative, but simpler: re-read via
                 ;; a helper.  For portability, we use the byte-buffer-reader
                 ;; which gives us slices sequentially.
                 ;; Actually, for a simpler approach, use grpc_byte_buffer_length
                 ;; and read all at once.  But the reader API is the official way.
                 ;;
                 ;; The slice struct has: refcount (ptr), data.refcounted.bytes (ptr),
                 ;; data.refcounted.length (size_t), or inline data.
                 ;; For safety, we read bytes via the inline/refcounted union.
                 ;; Byte 0-7: refcount pointer (NULL for inline)
                 ;; If refcount is NULL (inline slice):
                 ;;   Byte 8: length, Bytes 9-31: data
                 ;; Else (refcounted):
                 ;;   Byte 8-15: bytes pointer, Byte 16-23: length
                 (let* ((refcount-ptr (cffi:mem-ref slice-out :pointer 0)))
                   (if (cffi:null-pointer-p refcount-ptr)
                       ;; Inline slice
                       (let ((inline-len (cffi:mem-ref slice-out :uint8 8)))
                         (dotimes (j inline-len)
                           (vector-push-extend
                            (cffi:mem-ref slice-out :uint8 (+ 9 j))
                            result)))
                       ;; Refcounted slice
                       (let* ((data-ptr (cffi:mem-ref slice-out :pointer 8))
                              (data-len (cffi:mem-ref slice-out :size 16)))
                         (dotimes (j data-len)
                           (vector-push-extend
                            (cffi:mem-aref data-ptr :uint8 j)
                            result)))))))
      (%grpc-bb-reader-destroy reader)
      (coerce result '(simple-array (unsigned-byte 8) (*))))))

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

(defun %grpc-unary-call-raw (channel cq method-str request-bytes deadline-ms)
  "Execute a raw unary gRPC call. Returns (values response-bytes status-code status-message).
METHOD-STR is the full method path. REQUEST-BYTES is an octet vector.
DEADLINE-MS is timeout in milliseconds (0 = infinite)."
  (let* ((method-slice (%make-method-slice method-str))
         (deadline (if (and deadline-ms (> deadline-ms 0))
                       (gpr-deadline-from-ms deadline-ms)
                       (gpr-inf-future)))
         (call (%grpc-channel-create-call
                channel (cffi:null-pointer) 0 cq
                method-slice (cffi:null-pointer) deadline (cffi:null-pointer)))
         (request-bb (bytes-to-grpc-byte-buffer request-bytes)))
    (when (cffi:null-pointer-p call)
      (%grpc-slice-unref method-slice)
      (grpc-byte-buffer-destroy request-bb)
      (error 'rpc-error
             :message "Failed to create gRPC call"
             :status-code "INTERNAL" :details "grpc_channel_create_call returned NULL"))
    ;; Allocate ops array (6 ops × 40 bytes), metadata arrays, recv pointers
    (let ((ops-size (* 6 +grpc-op-size+)))
      (cffi:with-foreign-objects ((ops :uint8 ops-size)
                                  (recv-initial-metadata '(:struct grpc-metadata-array))
                                  (recv-message :pointer)
                                  (recv-status  :int32)
                                  (recv-status-details '(:struct grpc-slice))
                                  (trailing-metadata '(:struct grpc-metadata-array)))
        ;; Zero everything
        (dotimes (i ops-size)
          (setf (cffi:mem-aref ops :uint8 i) 0))
        (%grpc-metadata-array-init recv-initial-metadata)
        (%grpc-metadata-array-init trailing-metadata)
        (setf (cffi:mem-ref recv-message :pointer) (cffi:null-pointer))

        ;; Op 0: SEND_INITIAL_METADATA (empty)
        (let ((op0 ops))
          (setf (cffi:mem-ref op0 :int32 0) +grpc-op-send-initial-metadata+)
          ;; data.send_initial_metadata.count = 0 (already zeroed)
          )

        ;; Op 1: SEND_MESSAGE
        (let ((op1 (cffi:inc-pointer ops +grpc-op-size+)))
          (setf (cffi:mem-ref op1 :int32 0) +grpc-op-send-message+)
          ;; data.send_message.send_message = request_bb (pointer at data offset)
          (setf (cffi:mem-ref op1 :pointer +grpc-op-data-offset+) request-bb))

        ;; Op 2: SEND_CLOSE_FROM_CLIENT
        (let ((op2 (cffi:inc-pointer ops (* 2 +grpc-op-size+))))
          (setf (cffi:mem-ref op2 :int32 0) +grpc-op-send-close-from-client+))

        ;; Op 3: RECV_INITIAL_METADATA
        (let ((op3 (cffi:inc-pointer ops (* 3 +grpc-op-size+))))
          (setf (cffi:mem-ref op3 :int32 0) +grpc-op-recv-initial-metadata+)
          ;; data.recv_initial_metadata.recv_initial_metadata = &recv_initial_metadata
          (setf (cffi:mem-ref op3 :pointer +grpc-op-data-offset+) recv-initial-metadata))

        ;; Op 4: RECV_MESSAGE
        (let ((op4 (cffi:inc-pointer ops (* 4 +grpc-op-size+))))
          (setf (cffi:mem-ref op4 :int32 0) +grpc-op-recv-message+)
          ;; data.recv_message.recv_message = &recv_message (pointer-to-pointer)
          (setf (cffi:mem-ref op4 :pointer +grpc-op-data-offset+) recv-message))

        ;; Op 5: RECV_STATUS_ON_CLIENT
        (let ((op5 (cffi:inc-pointer ops (* 5 +grpc-op-size+))))
          (setf (cffi:mem-ref op5 :int32 0) +grpc-op-recv-status-on-client+)
          ;; data.recv_status_on_client:
          ;;   offset+0: trailing_metadata (pointer)
          ;;   offset+8: status (pointer to grpc_status_code)
          ;;   offset+16: status_details (pointer to grpc_slice)
          (setf (cffi:mem-ref op5 :pointer +grpc-op-data-offset+) trailing-metadata)
          (setf (cffi:mem-ref op5 :pointer (+ +grpc-op-data-offset+ 8))
                (cffi:foreign-alloc :int32 :initial-element 0))
          (setf (cffi:mem-ref op5 :pointer (+ +grpc-op-data-offset+ 16)) recv-status-details))

        ;; Grab the status-code pointer for later reading
        (let ((status-code-ptr (cffi:mem-ref
                                (cffi:inc-pointer ops (* 5 +grpc-op-size+))
                                :pointer (+ +grpc-op-data-offset+ 8))))

          ;; Start the batch
          (let ((batch-err (%grpc-call-start-batch
                            call ops 6 (cffi:null-pointer) (cffi:null-pointer))))
            (unless (zerop batch-err)
              ;; Cleanup
              (cffi:foreign-free status-code-ptr)
              (%grpc-metadata-array-destroy recv-initial-metadata)
              (%grpc-metadata-array-destroy trailing-metadata)
              (%grpc-call-unref call)
              (%grpc-slice-unref method-slice)
              (grpc-byte-buffer-destroy request-bb)
              (error 'rpc-error
                     :message (format nil "grpc_call_start_batch failed: ~A" batch-err)
                     :status-code "INTERNAL" :details "Batch start failure")))

          ;; Wait for completion
          (let* ((event (%grpc-cq-next cq (gpr-inf-future) (cffi:null-pointer)))
                 (event-type (cffi:foreign-slot-value event '(:struct grpc-event) 'type))
                 (event-success (cffi:foreign-slot-value event '(:struct grpc-event) 'success)))

            ;; Read results
            (let* ((final-status (cffi:mem-ref status-code-ptr :int32))
                   (recv-bb (cffi:mem-ref recv-message :pointer))
                   (response-bytes (if (and (not (cffi:null-pointer-p recv-bb))
                                            (= event-type +grpc-op-complete+)
                                            (not (zerop event-success)))
                                       (grpc-byte-buffer-to-bytes recv-bb)
                                       (make-array 0 :element-type '(unsigned-byte 8)))))

              ;; Cleanup
              (unless (cffi:null-pointer-p recv-bb)
                (%grpc-byte-buffer-destroy recv-bb))
              (cffi:foreign-free status-code-ptr)
              (%grpc-metadata-array-destroy recv-initial-metadata)
              (%grpc-metadata-array-destroy trailing-metadata)
              (%grpc-call-unref call)
              (%grpc-slice-unref method-slice)
              (%grpc-byte-buffer-destroy request-bb)

              (values response-bytes final-status))))))))

(defun grpc-byte-buffer-destroy (bb)
  "Safe wrapper — checks for null before destroying."
  (unless (cffi:null-pointer-p bb)
    (%grpc-byte-buffer-destroy bb)))
