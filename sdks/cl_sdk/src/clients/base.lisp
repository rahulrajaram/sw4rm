;;;; base.lisp - Base gRPC client infrastructure for SW4RM
;;;;
;;;; Provides base client class, connection management, retry logic,
;;;; and deadline handling for all SW4RM gRPC service clients.

(in-package :sw4rm-sdk)

;;;; Conditions
;;;; rpc-error is defined in errors.lisp (inherits from sw4rm-error)

(define-condition rpc-timeout (rpc-error)
  ()
  (:documentation "Condition signaled when an RPC call times out."))

(define-condition rpc-unavailable (rpc-error)
  ()
  (:documentation "Condition signaled when the RPC service is unavailable."))

;;;; Base Client Class

(defclass base-client ()
  ((address
    :initarg :address
    :accessor client-address
    :type string
    :documentation "gRPC service address (e.g., \"localhost:50051\").")
   (timeout-ms
    :initarg :timeout-ms
    :accessor client-timeout-ms
    :initform 30000
    :type (integer 1 *)
    :documentation "Default timeout in milliseconds for RPC calls.")
   (retry-max-attempts
    :initarg :retry-max-attempts
    :accessor client-retry-max-attempts
    :initform 3
    :type (integer 1 *)
    :documentation "Maximum number of retry attempts for transient failures.")
   (channel
    :initarg :channel
    :accessor client-channel
    :initform nil
    :documentation "gRPC channel instance (implementation-specific)."))
  (:documentation "Base class for all SW4RM gRPC service clients.

Provides common functionality for connection management, metadata handling,
timeouts, and retry logic. All service-specific clients should inherit from
this class.

Implementation Note:
Since Common Lisp gRPC libraries (cl-grpc, cl-protobufs) have limited
availability and maturity, this base class defines the interface that
concrete implementations must follow. Actual gRPC calls are stubbed out
and should be implemented when a suitable gRPC library is integrated."))

;;;; Connection Management

(defgeneric connect (client)
  (:documentation "Establish gRPC connection to the service.

Opens a gRPC channel to the service address specified in the client.
This is typically called automatically by the first RPC call, but can
be called explicitly for eager connection establishment.

Args:
  client: The client instance to connect.

Signals:
  RPC-ERROR: If connection cannot be established.

Returns:
  The client instance for chaining."))

(defmethod connect ((client base-client))
  "Create a gRPC channel to the service address.

When libgrpc is available, creates a real grpc-channel instance.
Falls back to a string placeholder when libgrpc is not loaded."
  (unless (client-channel client)
    (setf (client-channel client)
          (if *grpc-available*
              (make-grpc-channel (client-address client))
              (format nil "grpc-channel://~A" (client-address client)))))
  client)

(defgeneric disconnect (client)
  (:documentation "Close the gRPC connection.

Cleanly shuts down the gRPC channel and releases associated resources.
After disconnection, the client can be reconnected with CONNECT.

Args:
  client: The client instance to disconnect.

Returns:
  The client instance for chaining."))

(defmethod disconnect ((client base-client))
  "Destroy the gRPC channel (if real) and clear the slot."
  (let ((ch (client-channel client)))
    (when (and ch (typep ch 'grpc-channel))
      (destroy-grpc-channel ch)))
  (setf (client-channel client) nil)
  client)

;;;; Metadata Management

(defgeneric make-metadata (client &rest kvpairs)
  (:documentation "Create gRPC metadata (headers) for RPC calls.

Constructs an association list of key-value pairs to be sent as gRPC
metadata with RPC requests. Common metadata includes authentication
tokens, correlation IDs, and agent identifiers.

Args:
  client: The client instance.
  kvpairs: Alternating keyword-value pairs for metadata entries.

Returns:
  Association list of (key . value) pairs.

Example:
  (make-metadata client
                 :correlation-id \"wf-123\"
                 :agent-id \"agent-1\")
  => ((:correlation-id . \"wf-123\") (:agent-id . \"agent-1\"))"))

(defmethod make-metadata ((client base-client) &rest kvpairs)
  "Convert keyword-value pairs to metadata alist."
  (loop for (key value) on kvpairs by #'cddr
        when (and key value)
        collect (cons key value)))

;;;; Deadline and Retry Utilities

(defmacro with-deadline ((timeout-ms) &body body)
  "Execute BODY with a deadline (timeout).

If BODY does not complete within TIMEOUT-MS milliseconds, signals
RPC-TIMEOUT. This is used internally by RPC call implementations.

Args:
  timeout-ms: Maximum execution time in milliseconds.

Signals:
  RPC-TIMEOUT: If execution exceeds the deadline.

Returns:
  The value(s) returned by BODY.

Example:
  (with-deadline (5000)
    (call-remote-service))

Implementation Note:
This is a simplified implementation. A production version would use
threading or async I/O to enforce hard deadlines."
  (let ((start (gensym "START-"))
        (elapsed (gensym "ELAPSED-")))
    `(let ((,start (get-internal-real-time)))
       (unwind-protect
            (progn ,@body)
         (let ((,elapsed (floor (* 1000 (- (get-internal-real-time) ,start))
                               internal-time-units-per-second)))
           (when (> ,elapsed ,timeout-ms)
             (error 'rpc-timeout
                    :message (format nil "Operation exceeded deadline of ~Ams" ,timeout-ms)
                    :status-code "DEADLINE_EXCEEDED" :details "Timeout")))))))

(defmacro with-retry ((max-attempts &key (backoff-ms 100) (backoff-multiplier 2.0)) &body body)
  "Execute BODY with exponential backoff retry on transient failures.

Attempts to execute BODY up to MAX-ATTEMPTS times. On transient RPC
failures (unavailable, timeout), waits for BACKOFF-MS milliseconds
before retrying, multiplying the backoff by BACKOFF-MULTIPLIER each
attempt.

Args:
  max-attempts: Maximum number of attempts (including initial try).
  backoff-ms: Initial backoff delay in milliseconds (default: 100).
  backoff-multiplier: Factor to multiply backoff after each retry (default: 2.0).

Signals:
  RPC-ERROR: Re-signals the last error if all retry attempts fail.

Returns:
  The value(s) returned by BODY on success.

Example:
  (with-retry (3 :backoff-ms 200)
    (call-unreliable-service))"
  (let ((attempt (gensym "ATTEMPT-"))
        (delay (gensym "DELAY-"))
        (last-error (gensym "LAST-ERROR-")))
    `(let ((,attempt 0)
           (,delay ,backoff-ms)
           (,last-error nil))
       (loop
         (handler-case
             (return (progn ,@body))
           (rpc-unavailable (e)
             (setf ,last-error e)
             (incf ,attempt)
             (when (>= ,attempt ,max-attempts)
               (error ,last-error))
             (sleep (/ ,delay 1000.0))
             (setf ,delay (floor (* ,delay ,backoff-multiplier))))
           (rpc-timeout (e)
             (setf ,last-error e)
             (incf ,attempt)
             (when (>= ,attempt ,max-attempts)
               (error ,last-error))
             (sleep (/ ,delay 1000.0))
             (setf ,delay (floor (* ,delay ,backoff-multiplier)))))))))

;;;; Utility Functions

(defun ensure-connected (client)
  "Ensure CLIENT has an active gRPC channel.

If the client is not connected, establishes a connection. This is called
internally before each RPC call.

Args:
  client: The client instance to check.

Returns:
  The client instance."
  (unless (client-channel client)
    (connect client))
  client)
