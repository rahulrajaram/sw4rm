;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; grpc/client.lisp
;;;;
;;;; gRPC Client for Common Lisp Orchestrator -> Python sw4rm Leaf Communication
;;;;
;;;; This module implements the gRPC client layer for the orchestrator to
;;;; communicate with Python sw4rm leaf instances. The client handles:
;;;;   - Connection lifecycle (connect, disconnect, reconnect)
;;;;   - Envelope serialization/deserialization to protobuf
;;;;   - Service method invocations (deliver-envelope, get-status, shutdown)
;;;;   - Async operations with callbacks
;;;;   - Error handling and retry logic
;;;;   - Health checking and heartbeat monitoring
;;;;
;;;; Architecture:
;;;;   The LEAF-GRPC-CLIENT wraps a gRPC channel to a remote Python sw4rm
;;;;   instance. It translates Lisp envelopes to protobuf messages and vice versa.
;;;;
;;;; Note:
;;;;   This is a well-structured placeholder implementation. The actual gRPC
;;;;   integration will be implemented when cl-grpc or equivalent library
;;;;   is available. The interfaces are designed to match the expected gRPC
;;;;   semantics and are ready for integration.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0
;;;;
;;;; Spec References:
;;;;   - COMMON_LISP_PLAN.md §4.2: gRPC Client Design
;;;;   - spec.md §11: Messaging Model
;;;;   - spec.md §5.2: Message correlation and tracing

(in-package :sw4rm-orchestrator.grpc)

;;;; ============================================================================
;;;; LEAF-GRPC-CLIENT Class
;;;; ============================================================================

(defclass leaf-grpc-client ()
  ((swarm-id
    :initarg :swarm-id
    :accessor client-swarm-id
    :type string
    :documentation "Unique identifier for the target leaf swarm.

    This ID is used for routing, logging, and identification. Must match
    the swarm ID of the remote Python instance.")

   (host
    :initarg :host
    :accessor client-host
    :initform "localhost"
    :type string
    :documentation "Hostname or IP address of the Python leaf swarm.

    Defaults to localhost for local development. In production, this
    should be set to the actual service address (e.g., Kubernetes service name).")

   (port
    :initarg :port
    :accessor client-port
    :initform 50051
    :type (integer 1 65535)
    :documentation "Port number for the gRPC service.

    Defaults to 50051 (standard gRPC development port). Must be in the
    valid port range [1, 65535].")

   (channel
    :accessor client-channel
    :initform nil
    :type (or null t)
    :documentation "Active gRPC channel to the Python leaf swarm.

    NIL when disconnected. When connected, this holds the gRPC channel
    object (type depends on gRPC library used). Managed by CONNECT/DISCONNECT.")

   (stub
    :accessor client-stub
    :initform nil
    :type (or null t)
    :documentation "Service stub for LeafService RPC calls.

    NIL when disconnected. When connected, this holds the stub object
    for making LeafService method calls. Generated from the protobuf
    service definition.")

   (connected-p
    :accessor client-connected-p
    :initform nil
    :type boolean
    :documentation "Connection status flag.

    T if the client has an active gRPC connection, NIL otherwise.
    Use IS-CONNECTED-P for public access.")

   (last-error
    :accessor client-last-error
    :initform nil
    :type (or null condition)
    :documentation "Last error condition encountered during operations.

    NIL if no errors have occurred. Used for diagnostics and debugging.
    Reset on successful operations.")

   (connection-attempts
    :accessor client-connection-attempts
    :initform 0
    :type (integer 0 *)
    :documentation "Number of connection attempts made.

    Incremented on each CONNECT call. Reset on successful connection or
    explicit DISCONNECT. Used for backoff and retry logic.")

   (max-retries
    :accessor client-max-retries
    :initform 3
    :type (integer 1 *)
    :documentation "Maximum number of retry attempts for failed operations.

    Defaults to 3. Used by automatic retry mechanisms. Can be configured
    per-client or globally.")

   (created-at
    :reader client-created-at
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when this client was created.

    Automatically set at construction time. Used for metrics and diagnostics."))

  (:documentation "gRPC client for communicating with Python sw4rm leaf instances.

  The LEAF-GRPC-CLIENT provides a high-level interface for orchestrator-to-leaf
  communication. It manages the gRPC connection lifecycle and translates between
  Lisp data structures and protobuf messages.

  Lifecycle:
    1. Create client: (make-instance 'leaf-grpc-client :swarm-id \"leaf-a\" ...)
    2. Connect: (connect client)
    3. Use service methods: (deliver-envelope client envelope)
    4. Disconnect: (disconnect client)

  Service Methods:
    - DELIVER-ENVELOPE: Send envelope to leaf for local routing
    - GET-STATUS: Query leaf health and metrics
    - REQUEST-SHUTDOWN: Request graceful shutdown of leaf

  Connection Management:
    - CONNECT: Establish gRPC connection
    - DISCONNECT: Close connection
    - RECONNECT: Disconnect and reconnect
    - ENSURE-CONNECTED: Connect if not already connected

  Error Handling:
    - All methods signal SW4RM-ERROR conditions on failure
    - SWARM-DISCONNECTED: Connection was lost
    - SWARM-UNREACHABLE: Cannot reach target
    - Restarts available: RETRY-WITH-BACKOFF, QUEUE-FOR-RETRY, DROP-MESSAGE

  Examples:
    ;; Basic usage
    (let ((client (make-instance 'leaf-grpc-client
                                 :swarm-id \"leaf-a\"
                                 :host \"localhost\"
                                 :port 50051)))
      (connect client)
      (deliver-envelope client envelope)
      (disconnect client))

    ;; With error handling
    (handler-bind
        ((swarm-unreachable
           (lambda (c)
             (invoke-restart 'retry-with-backoff 5))))
      (deliver-envelope client envelope))

  See Also:
    CONNECT, DISCONNECT, DELIVER-ENVELOPE, GET-STATUS"))

;;;; ============================================================================
;;;; Connection Management
;;;; ============================================================================

(defgeneric connect (client)
  (:documentation "Establish gRPC connection to Python leaf swarm.

  Opens a gRPC channel to the remote leaf instance and initializes the
  service stub. This must be called before any service methods can be invoked.

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    The client instance (for chaining).

  Signals:
    SWARM-UNREACHABLE if connection cannot be established.

  Side Effects:
    - Sets CLIENT-CHANNEL to the gRPC channel
    - Sets CLIENT-STUB to the service stub
    - Sets CLIENT-CONNECTED-P to T
    - Increments CLIENT-CONNECTION-ATTEMPTS
    - Resets CLIENT-LAST-ERROR on success

  Notes:
    This is a placeholder implementation. The actual gRPC connection will
    be established using cl-grpc or equivalent when available.

  Examples:
    (connect client)
    => #<LEAF-GRPC-CLIENT leaf-a@localhost:50051>

  See Also:
    DISCONNECT, RECONNECT, IS-CONNECTED-P"))

(defmethod connect ((client leaf-grpc-client))
  "Establish gRPC connection to Python leaf swarm."
  (let* ((address (format nil "~A:~A"
                          (client-host client)
                          (client-port client)))
         (swarm-id (client-swarm-id client)))

    ;; Increment connection attempts
    (incf (client-connection-attempts client))

    ;; Placeholder: In production, create actual gRPC channel
    ;; Example (pseudo-code):
    ;;   (setf channel (grpc:make-channel address))
    ;;   (setf stub (make-leaf-service-stub channel))

    ;; Placeholder implementation
    (handler-case
        (progn
          ;; Simulate connection creation
          ;; In actual implementation: channel = grpc:make-channel(address)
          (let ((channel (make-hash-table))  ; Placeholder channel
                (stub (make-hash-table)))    ; Placeholder stub
            ;; Mark as connected
            (setf (client-channel client) channel
                  (client-stub client) stub
                  (client-connected-p client) t
                  (client-last-error client) nil)

            ;; Log connection
            (log:info "Connected to leaf ~A at ~A" swarm-id address)

            client))

      (error (e)
        ;; Connection failed - signal SWARM-UNREACHABLE
        (setf (client-last-error client) e
              (client-connected-p client) nil)
        (error 'sw4rm-orchestrator.errors:swarm-unreachable
               :swarm-id swarm-id
               :message (format nil "Failed to connect to ~A: ~A" address e)
               :context (list :host (client-host client)
                              :port (client-port client)
                              :attempt (client-connection-attempts client)))))))

(defgeneric disconnect (client)
  (:documentation "Close gRPC connection to Python leaf swarm.

  Cleanly shuts down the gRPC channel and clears connection state.
  Safe to call on already-disconnected clients (no-op).

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    NIL

  Side Effects:
    - Closes CLIENT-CHANNEL if open
    - Sets CLIENT-CHANNEL to NIL
    - Sets CLIENT-STUB to NIL
    - Sets CLIENT-CONNECTED-P to NIL
    - Resets CLIENT-CONNECTION-ATTEMPTS

  Examples:
    (disconnect client)
    => NIL

  See Also:
    CONNECT, RECONNECT"))

(defmethod disconnect ((client leaf-grpc-client))
  "Close gRPC connection to Python leaf swarm."
  (when (client-connected-p client)
    ;; Placeholder: In production, close actual gRPC channel
    ;; Example: (grpc:close-channel (client-channel client))

    (let ((swarm-id (client-swarm-id client)))
      ;; Log disconnection
      (log:info "Disconnecting from leaf ~A" swarm-id)

      ;; Clear connection state
      (setf (client-channel client) nil
            (client-stub client) nil
            (client-connected-p client) nil
            (client-connection-attempts client) 0)))

  nil)

(defgeneric reconnect (client)
  (:documentation "Disconnect and reconnect to Python leaf swarm.

  Convenience method that calls DISCONNECT followed by CONNECT.
  Useful for recovering from connection errors or configuration changes.

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    The client instance (for chaining).

  Signals:
    SWARM-UNREACHABLE if reconnection fails.

  Examples:
    (reconnect client)
    => #<LEAF-GRPC-CLIENT leaf-a@localhost:50051>

  See Also:
    CONNECT, DISCONNECT"))

(defmethod reconnect ((client leaf-grpc-client))
  "Disconnect and reconnect to Python leaf swarm."
  (disconnect client)
  (connect client))

(defgeneric ensure-connected (client)
  (:documentation "Ensure client is connected, connecting if necessary.

  Idempotent connection establishment. If already connected, does nothing.
  If not connected, calls CONNECT.

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    The client instance (for chaining).

  Signals:
    SWARM-UNREACHABLE if connection cannot be established.

  Examples:
    (ensure-connected client)
    => #<LEAF-GRPC-CLIENT leaf-a@localhost:50051>

  See Also:
    CONNECT, IS-CONNECTED-P"))

(defmethod ensure-connected ((client leaf-grpc-client))
  "Ensure client is connected, connecting if necessary."
  (unless (client-connected-p client)
    (connect client))
  client)

(defun is-connected-p (client)
  "Check if client has an active gRPC connection.

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    T if connected, NIL otherwise.

  Examples:
    (is-connected-p client) => T

  See Also:
    CONNECT, DISCONNECT, ENSURE-CONNECTED"
  (declare (type leaf-grpc-client client))
  (client-connected-p client))

;;;; ============================================================================
;;;; Service Methods - LeafService RPC Calls
;;;; ============================================================================

(defgeneric deliver-envelope (client envelope)
  (:documentation "Deliver envelope to Python leaf via gRPC.

  Sends a cross-swarm envelope to the leaf for local delivery or routing.
  The envelope is serialized to protobuf and sent via gRPC.

  Args:
    client - LEAF-GRPC-CLIENT instance (must be connected)
    envelope - CROSS-SWARM-ENVELOPE to deliver

  Returns:
    Delivery acknowledgement (hash-table with :success, :message-id, etc.)

  Signals:
    SWARM-DISCONNECTED if client is not connected.
    SWARM-UNREACHABLE if delivery fails due to network/remote errors.
    ENVELOPE-ERROR if envelope is malformed.

  Restarts Available:
    RETRY-WITH-BACKOFF - Retry delivery with exponential backoff
    QUEUE-FOR-RETRY - Queue envelope for later delivery
    DROP-MESSAGE - Discard envelope

  Side Effects:
    - Increments delivery metrics
    - Updates CLIENT-LAST-ERROR on failure

  Examples:
    (deliver-envelope client envelope)
    => #<HASH-TABLE :SUCCESS T :MESSAGE-ID \"msg-123\">

  See Also:
    DELIVER-ENVELOPE-ASYNC, ENVELOPE-TO-PROTO"))

(defmethod deliver-envelope ((client leaf-grpc-client)
                              (envelope sw4rm-orchestrator.envelope:cross-swarm-envelope))
  "Deliver envelope to Python leaf via gRPC."
  ;; Ensure we're connected
  (unless (client-connected-p client)
    (error 'sw4rm-orchestrator.errors:swarm-disconnected
           :swarm-id (client-swarm-id client)
           :reason :not-connected
           :message "Client is not connected"))

  ;; Convert envelope to protobuf
  (let ((proto-envelope (envelope-to-proto envelope)))

    ;; Placeholder: In production, make actual gRPC call
    ;; Example: (grpc:call (client-stub client) 'deliver-envelope proto-envelope)

    (handler-case
        (progn
          ;; Simulate gRPC call
          ;; In actual implementation: result = stub.DeliverEnvelope(proto-envelope)

          ;; Placeholder response
          (let ((response (make-hash-table :test 'equal)))
            (setf (gethash "success" response) t
                  (gethash "message_id" response)
                  (sw4rm-orchestrator.envelope:envelope-id envelope)
                  (gethash "timestamp" response) (get-universal-time))

            ;; Log delivery
            (log:info "Delivered envelope ~A to leaf ~A"
                      (sw4rm-orchestrator.envelope:envelope-id envelope)
                      (client-swarm-id client))

            ;; Clear last error on success
            (setf (client-last-error client) nil)

            response))

      (error (e)
        ;; Delivery failed
        (setf (client-last-error client) e)
        (error 'sw4rm-orchestrator.errors:swarm-unreachable
               :swarm-id (client-swarm-id client)
               :message (format nil "Failed to deliver envelope: ~A" e)
               :context (list :envelope-id
                              (sw4rm-orchestrator.envelope:envelope-id envelope)))))))

(defgeneric get-status (client)
  (:documentation "Query leaf status and health metrics via gRPC.

  Retrieves the current status of the Python leaf swarm, including:
    - Health status (:healthy, :degraded, :unavailable)
    - Number of active agents
    - Task queue depth
    - Resource utilization metrics
    - Last heartbeat timestamp

  Args:
    client - LEAF-GRPC-CLIENT instance (must be connected)

  Returns:
    Hash-table with status information.

  Signals:
    SWARM-DISCONNECTED if client is not connected.
    SWARM-UNREACHABLE if status query fails.

  Examples:
    (get-status client)
    => #<HASH-TABLE :STATUS :HEALTHY :AGENT-COUNT 5 :QUEUE-DEPTH 12>

  See Also:
    PING, CLIENT-HEALTHY-P"))

(defmethod get-status ((client leaf-grpc-client))
  "Query leaf status and health metrics via gRPC."
  ;; Ensure we're connected
  (unless (client-connected-p client)
    (error 'sw4rm-orchestrator.errors:swarm-disconnected
           :swarm-id (client-swarm-id client)
           :reason :not-connected
           :message "Client is not connected"))

  ;; Placeholder: In production, make actual gRPC call
  ;; Example: (grpc:call (client-stub client) 'get-status (make-status-request))

  (handler-case
      (progn
        ;; Simulate gRPC call
        ;; In actual implementation: result = stub.GetStatus(StatusRequest())

        ;; Placeholder response
        (let ((status (make-hash-table :test 'equal)))
          (setf (gethash "status" status) :healthy
                (gethash "agent_count" status) 0
                (gethash "queue_depth" status) 0
                (gethash "timestamp" status) (get-universal-time))

          ;; Clear last error on success
          (setf (client-last-error client) nil)

          status))

    (error (e)
      ;; Status query failed
      (setf (client-last-error client) e)
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (client-swarm-id client)
             :message (format nil "Failed to get status: ~A" e)))))

(defgeneric request-shutdown (client &key graceful timeout)
  (:documentation "Request shutdown of Python leaf swarm via gRPC.

  Sends a shutdown request to the leaf. The leaf may either:
    - Shut down gracefully (finish current tasks, drain queues)
    - Shut down immediately (cancel in-progress work)

  Args:
    client - LEAF-GRPC-CLIENT instance (must be connected)
    graceful - If T, request graceful shutdown (default: T)
    timeout - Maximum seconds to wait for graceful shutdown (default: 30)

  Returns:
    Shutdown response (hash-table with :acknowledged, :estimated-time, etc.)

  Signals:
    SWARM-DISCONNECTED if client is not connected.
    SWARM-UNREACHABLE if shutdown request fails.

  Side Effects:
    - Leaf swarm will begin shutdown procedure
    - Connection may be lost immediately (for non-graceful shutdown)

  Examples:
    (request-shutdown client :graceful t :timeout 60)
    => #<HASH-TABLE :ACKNOWLEDGED T :ESTIMATED-TIME 45>

  See Also:
    DISCONNECT"))

(defmethod request-shutdown ((client leaf-grpc-client)
                              &key (graceful t) (timeout 30))
  "Request shutdown of Python leaf swarm via gRPC."
  ;; Ensure we're connected
  (unless (client-connected-p client)
    (error 'sw4rm-orchestrator.errors:swarm-disconnected
           :swarm-id (client-swarm-id client)
           :reason :not-connected
           :message "Client is not connected"))

  ;; Placeholder: In production, make actual gRPC call
  ;; Example: (grpc:call (client-stub client) 'request-shutdown
  ;;                     (make-shutdown-request :graceful graceful :timeout timeout))

  (handler-case
      (progn
        ;; Simulate gRPC call
        ;; In actual implementation: result = stub.RequestShutdown(request)

        ;; Log shutdown request
        (log:info "Requesting ~A shutdown of leaf ~A (timeout: ~As)"
                  (if graceful "graceful" "immediate")
                  (client-swarm-id client)
                  timeout)

        ;; Placeholder response
        (let ((response (make-hash-table :test 'equal)))
          (setf (gethash "acknowledged" response) t
                (gethash "graceful" response) graceful
                (gethash "estimated_time" response) (if graceful timeout 0)
                (gethash "timestamp" response) (get-universal-time))

          ;; Clear last error on success
          (setf (client-last-error client) nil)

          response))

    (error (e)
      ;; Shutdown request failed
      (setf (client-last-error client) e)
      (error 'sw4rm-orchestrator.errors:swarm-unreachable
             :swarm-id (client-swarm-id client)
             :message (format nil "Failed to request shutdown: ~A" e)))))

;;;; ============================================================================
;;;; Async Operations
;;;; ============================================================================

(defgeneric deliver-envelope-async (client envelope callback)
  (:documentation "Deliver envelope asynchronously with callback.

  Sends envelope to leaf without blocking. The callback is invoked when
  the operation completes (either success or failure).

  Args:
    client - LEAF-GRPC-CLIENT instance (must be connected)
    envelope - CROSS-SWARM-ENVELOPE to deliver
    callback - Function called with (success-p result-or-error)

  Returns:
    Future or promise object (implementation-specific).

  Side Effects:
    - Envelope is sent asynchronously
    - Callback is invoked on completion (in background thread)

  Examples:
    (deliver-envelope-async client envelope
      (lambda (success-p result)
        (if success-p
            (format t \"Delivered: ~A~%\" result)
            (format t \"Failed: ~A~%\" result))))

  See Also:
    DELIVER-ENVELOPE"))

(defmethod deliver-envelope-async ((client leaf-grpc-client)
                                    (envelope sw4rm-orchestrator.envelope:cross-swarm-envelope)
                                    callback)
  "Deliver envelope asynchronously with callback."
  ;; Placeholder: In production, use async gRPC or threading
  ;; Example: (grpc:call-async (client-stub client) 'deliver-envelope
  ;;                           proto-envelope callback)

  ;; Simple implementation: synchronous call in background thread
  (let ((client-ref client)
        (envelope-ref envelope))
    (bt:make-thread
      (lambda ()
        (handler-case
            (let ((result (deliver-envelope client-ref envelope-ref)))
              (funcall callback t result))
          (error (e)
            (funcall callback nil e))))
      :name (format nil "deliver-envelope-async-~A"
                    (sw4rm-orchestrator.envelope:envelope-id envelope)))))

(defmacro with-grpc-deadline ((timeout) &body body)
  "Execute body with gRPC deadline.

  Sets a deadline for gRPC operations within the body. If the deadline
  is exceeded, the operation is cancelled and DEADLINE-EXCEEDED is signaled.

  Args:
    timeout - Timeout in seconds (integer or float)
    body - Code to execute

  Returns:
    Result of body.

  Signals:
    DEADLINE-EXCEEDED if timeout is exceeded.

  Examples:
    (with-grpc-deadline (5)
      (deliver-envelope client envelope))

  See Also:
    DELIVER-ENVELOPE"
  `(handler-case
       (with-timeout (,timeout)
         ,@body)
     (timeout-error (e)
       (error 'sw4rm-orchestrator.errors:deadline-exceeded
              :deadline (+ (get-universal-time) ,timeout)
              :current-time (get-universal-time)
              :message (format nil "gRPC operation timed out after ~As" ,timeout)))))

;;;; ============================================================================
;;;; Error Handling
;;;; ============================================================================

(defun handle-grpc-error (condition client)
  "Handle gRPC errors and translate to SW4RM conditions.

  This function examines gRPC-specific error codes and translates them
  to appropriate SW4RM condition types.

  Args:
    condition - Error condition from gRPC layer
    client - LEAF-GRPC-CLIENT instance

  Returns:
    Does not return; signals a SW4RM-ERROR condition.

  Examples:
    (handler-case
        (grpc:call stub method arg)
      (grpc-error (e)
        (handle-grpc-error e client)))

  See Also:
    SWARM-UNREACHABLE, SWARM-DISCONNECTED"
  (declare (type leaf-grpc-client client))

  ;; Store error for diagnostics
  (setf (client-last-error client) condition)

  ;; Translate gRPC error to SW4RM condition
  ;; In production, check gRPC status codes:
  ;;   UNAVAILABLE -> SWARM-UNREACHABLE
  ;;   DEADLINE_EXCEEDED -> DEADLINE-EXCEEDED
  ;;   CANCELLED -> SWARM-DISCONNECTED
  ;;   etc.

  (error 'sw4rm-orchestrator.errors:swarm-unreachable
         :swarm-id (client-swarm-id client)
         :message (format nil "gRPC error: ~A" condition)))

;;;; ============================================================================
;;;; Health Checking
;;;; ============================================================================

(defun client-healthy-p (client)
  "Check if client is healthy and ready for operations.

  A client is considered healthy if:
    - It has an active connection (CONNECTED-P is T)
    - Recent operations have succeeded (LAST-ERROR is NIL)
    - The remote leaf responds to heartbeats

  Args:
    client - LEAF-GRPC-CLIENT instance

  Returns:
    T if healthy, NIL otherwise.

  Examples:
    (client-healthy-p client) => T

  See Also:
    IS-CONNECTED-P, PING"
  (declare (type leaf-grpc-client client))
  (and (client-connected-p client)
       (null (client-last-error client))))

(defgeneric ping (client &key timeout)
  (:documentation "Send heartbeat ping to leaf and measure latency.

  Sends a lightweight ping to the leaf to check connectivity and measure
  round-trip latency. This is typically used for health checks.

  Args:
    client - LEAF-GRPC-CLIENT instance (must be connected)
    timeout - Timeout in seconds (default: 5)

  Returns:
    (values latency-ms success-p)
      latency-ms - Round-trip latency in milliseconds (or NIL on failure)
      success-p - T if ping succeeded, NIL otherwise

  Examples:
    (multiple-value-bind (latency success-p)
        (ping client :timeout 5)
      (if success-p
          (format t \"Latency: ~Ams~%\" latency)
          (format t \"Ping failed~%\")))

  See Also:
    CLIENT-HEALTHY-P, GET-STATUS"))

(defmethod ping ((client leaf-grpc-client) &key (timeout 5))
  "Send heartbeat ping to leaf and measure latency."
  ;; Ensure we're connected
  (unless (client-connected-p client)
    (return-from ping (values nil nil)))

  ;; Placeholder: In production, make actual gRPC ping call
  ;; Example: (grpc:call (client-stub client) 'ping (make-ping-request))

  (let ((start-time (get-internal-real-time)))
    (handler-case
        (progn
          ;; Simulate ping (get status is effectively a ping)
          (get-status client)

          ;; Calculate latency
          (let* ((end-time (get-internal-real-time))
                 (latency-ms (/ (* 1000 (- end-time start-time))
                                internal-time-units-per-second)))
            (values latency-ms t)))

      (error (e)
        ;; Ping failed
        (setf (client-last-error client) e)
        (values nil nil)))))

;;;; ============================================================================
;;;; Serialization - Envelope to Protobuf
;;;; ============================================================================

(defun envelope-to-proto (envelope)
  "Convert Lisp envelope to protobuf message.

  Translates a CROSS-SWARM-ENVELOPE to a protobuf CrossSwarmEnvelope message.
  This is used before sending envelopes over gRPC.

  Args:
    envelope - CROSS-SWARM-ENVELOPE to convert

  Returns:
    Protobuf message object (hash-table in placeholder implementation).

  Notes:
    In production, this will create an actual protobuf message object
    using the generated protobuf classes.

  Examples:
    (envelope-to-proto envelope)
    => #<HASH-TABLE ...>

  See Also:
    PROTO-TO-ENVELOPE, DELIVER-ENVELOPE"
  (declare (type sw4rm-orchestrator.envelope:cross-swarm-envelope envelope))

  ;; Placeholder: In production, create actual protobuf message
  ;; Example: (make-cross-swarm-envelope-proto ...)

  ;; For now, return a hash-table representation
  (let ((proto (make-hash-table :test 'equal)))
    (setf (gethash "id" proto)
          (sw4rm-orchestrator.envelope:envelope-id envelope)

          (gethash "correlation_id" proto)
          (or (sw4rm-orchestrator.envelope:envelope-correlation-id envelope) "")

          (gethash "idempotency_token" proto)
          (or (sw4rm-orchestrator.envelope:envelope-idempotency-token envelope) "")

          (gethash "source_swarm" proto)
          (or (sw4rm-orchestrator.envelope:envelope-source-swarm envelope) "")

          (gethash "target_swarm" proto)
          (or (sw4rm-orchestrator.envelope:envelope-target-swarm envelope) "")

          (gethash "sender" proto)
          (or (sw4rm-orchestrator.envelope:envelope-sender envelope) "")

          (gethash "recipient" proto)
          (or (sw4rm-orchestrator.envelope:envelope-recipient envelope) "")

          (gethash "payload" proto)
          (payload-to-json (sw4rm-orchestrator.envelope:envelope-payload envelope))

          (gethash "path" proto)
          (coerce (sw4rm-orchestrator.envelope:envelope-path envelope) 'vector)

          (gethash "hop_count" proto)
          (sw4rm-orchestrator.envelope:envelope-hop-count envelope)

          (gethash "max_hops" proto)
          (sw4rm-orchestrator.envelope:envelope-max-hops envelope)

          (gethash "created_at" proto)
          (sw4rm-orchestrator.envelope:envelope-created-at envelope)

          (gethash "deadline" proto)
          (or (sw4rm-orchestrator.envelope:envelope-deadline envelope) 0))

    proto))

(defun proto-to-envelope (proto)
  "Convert protobuf message to Lisp envelope.

  Translates a protobuf CrossSwarmEnvelope message to a CROSS-SWARM-ENVELOPE.
  This is used when receiving envelopes over gRPC.

  Args:
    proto - Protobuf message object (hash-table in placeholder)

  Returns:
    CROSS-SWARM-ENVELOPE instance.

  Notes:
    In production, this will extract fields from actual protobuf message objects.

  Examples:
    (proto-to-envelope proto-msg)
    => #<CROSS-SWARM-ENVELOPE id: 550e8400...>

  See Also:
    ENVELOPE-TO-PROTO"
  ;; Placeholder: In production, extract from actual protobuf message
  ;; Example: (make-cross-swarm-envelope :id (proto-id proto) ...)

  (sw4rm-orchestrator.envelope:make-cross-swarm-envelope
    :correlation-id (let ((val (gethash "correlation_id" proto)))
                      (if (zerop (length val)) nil val))
    :idempotency-token (let ((val (gethash "idempotency_token" proto)))
                         (if (zerop (length val)) nil val))
    :source-swarm (let ((val (gethash "source_swarm" proto)))
                    (if (zerop (length val)) nil val))
    :target-swarm (let ((val (gethash "target_swarm" proto)))
                    (if (zerop (length val)) nil val))
    :sender (let ((val (gethash "sender" proto)))
              (if (zerop (length val)) nil val))
    :recipient (let ((val (gethash "recipient" proto)))
                 (if (zerop (length val)) nil val))
    :payload (payload-from-json (gethash "payload" proto))
    :path (coerce (gethash "path" proto) 'list)
    :hop-count (gethash "hop_count" proto)
    :max-hops (gethash "max_hops" proto)
    :created-at (gethash "created_at" proto)
    :deadline (let ((val (gethash "deadline" proto)))
                (if (zerop val) nil val))))

(defun payload-to-json (payload)
  "Serialize payload to JSON string.

  Args:
    payload - Any Lisp object

  Returns:
    JSON string representation.

  Examples:
    (payload-to-json '(:event \"login\" :user-id 42))
    => \"{\\\"event\\\": \\\"login\\\", \\\"user_id\\\": 42}\"

  See Also:
    PAYLOAD-FROM-JSON"
  ;; Placeholder: In production, use actual JSON library (cl-json, etc.)
  (format nil "~S" payload))

(defun payload-from-json (json-string)
  "Deserialize payload from JSON string.

  Args:
    json-string - JSON string

  Returns:
    Lisp object (usually plist or hash-table).

  Examples:
    (payload-from-json \"{\\\"event\\\": \\\"login\\\"}\")
    => (:EVENT \"login\")

  See Also:
    PAYLOAD-TO-JSON"
  ;; Placeholder: In production, use actual JSON library
  (read-from-string json-string))

;;;; ============================================================================
;;;; Convenience Macro
;;;; ============================================================================

(defmacro with-connected-client ((client-var swarm-id host port) &body body)
  "Execute body with connected gRPC client, ensuring cleanup.

  Creates a gRPC client, connects it, executes body, and ensures
  disconnection on exit (even if errors occur).

  Args:
    client-var - Symbol to bind the client to
    swarm-id - Swarm ID string
    host - Hostname string
    port - Port number
    body - Code to execute

  Returns:
    Result of body.

  Examples:
    (with-connected-client (client \"leaf-a\" \"localhost\" 50051)
      (deliver-envelope client envelope))

  See Also:
    CONNECT, DISCONNECT"
  `(let ((,client-var (make-instance 'leaf-grpc-client
                                     :swarm-id ,swarm-id
                                     :host ,host
                                     :port ,port)))
     (unwind-protect
          (progn
            (connect ,client-var)
            ,@body)
       (disconnect ,client-var))))

;;;; ============================================================================
;;;; Utility Functions
;;;; ============================================================================

;; Simple timeout implementation (placeholder)
(defmacro with-timeout ((seconds) &body body)
  "Execute body with timeout.

  This is a simplified placeholder. In production, use bordeaux-threads
  or similar for proper timeout handling.

  Args:
    seconds - Timeout in seconds
    body - Code to execute

  Signals:
    TIMEOUT-ERROR if timeout is exceeded."
  `(progn
     ;; Placeholder: In production, use actual timeout mechanism
     ;; Example: (bt:with-timeout (,seconds) ,@body)
     ,@body))

(define-condition timeout-error (error)
  ((timeout-seconds
    :initarg :timeout-seconds
    :reader timeout-error-seconds))
  (:report (lambda (condition stream)
             (format stream "Operation timed out after ~As"
                     (timeout-error-seconds condition))))
  (:documentation "Condition signaled when an operation times out."))

;;;; ============================================================================
;;;; End of file
;;;; ============================================================================
