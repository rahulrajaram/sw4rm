;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; grpc/server.lisp
;;;;
;;;; gRPC Server for Common Lisp Orchestrator - Accepting Calls from Python Leaves
;;;;
;;;; This module implements the gRPC server layer for the orchestrator to
;;;; accept incoming calls from Python sw4rm leaf instances. The server handles:
;;;;   - Server lifecycle (start, stop, graceful shutdown)
;;;;   - OrchestratorService implementation (leaf registration, routing, heartbeats)
;;;;   - Request/response message handling
;;;;   - Leaf connection tracking and registry
;;;;   - Streaming heartbeat monitoring
;;;;   - Error handling and validation
;;;;
;;;; Architecture:
;;;;   The ORCHESTRATOR-GRPC-SERVER wraps a gRPC server that implements the
;;;;   OrchestratorService interface. Python leaves connect to this server to:
;;;;     - Register themselves with the orchestrator
;;;;     - Request envelope routing
;;;;     - Send periodic heartbeats
;;;;     - Unregister on shutdown
;;;;
;;;; Note:
;;;;   This is a well-structured placeholder implementation. The actual gRPC
;;;;   server integration will be implemented when cl-grpc or equivalent library
;;;;   is available. The interfaces are designed to match the expected gRPC
;;;;   semantics and are ready for integration.
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0
;;;;
;;;; Spec References:
;;;;   - COMMON_LISP_PLAN.md §4.2: gRPC Server Design
;;;;   - spec.md §11: Messaging Model
;;;;   - spec.md §5.2: Message correlation and tracing

(in-package :sw4rm-orchestrator.grpc)

;;;; ============================================================================
;;;; Request/Response Types (as defstructs)
;;;; ============================================================================

(defstruct leaf-registration
  "Registration request from a Python leaf to the orchestrator.

  Fields:
    swarm-id - Unique identifier for the leaf swarm
    host - Hostname or IP address where leaf is listening
    port - Port number where leaf accepts gRPC connections
    capabilities - List of capabilities (strings or keywords)
    metadata - Additional metadata (plist or hash-table)"
  (swarm-id nil :type string)
  (host nil :type string)
  (port nil :type (integer 1 65535))
  (capabilities nil :type list)
  (metadata nil :type t))

(defstruct registration-response
  "Response to leaf registration request.

  Fields:
    success - T if registration succeeded, NIL otherwise
    assigned-id - Swarm ID assigned by orchestrator (may differ from requested)
    error-message - Error description if success is NIL
    timestamp - Universal time when registration was processed"
  (success nil :type boolean)
  (assigned-id nil :type (or null string))
  (error-message nil :type (or null string))
  (timestamp (get-universal-time) :type integer))

(defstruct heartbeat
  "Heartbeat message from leaf to orchestrator.

  Fields:
    swarm-id - ID of the leaf sending the heartbeat
    timestamp - Universal time when heartbeat was sent
    metrics-plist - Performance metrics as plist
                    (e.g., :cpu 0.5 :memory 1024 :queue-depth 10)
    status - Health status (:healthy, :degraded, :unavailable)"
  (swarm-id nil :type string)
  (timestamp (get-universal-time) :type integer)
  (metrics-plist nil :type list)
  (status :healthy :type (member :healthy :degraded :unavailable)))

(defstruct heartbeat-ack
  "Acknowledgement of heartbeat from orchestrator to leaf.

  Fields:
    acknowledged - T if heartbeat was received and processed
    timestamp - Universal time when acknowledgement was sent
    instructions - Optional instructions from orchestrator (plist)
                   (e.g., :throttle t :drain t)"
  (acknowledged t :type boolean)
  (timestamp (get-universal-time) :type integer)
  (instructions nil :type list))

;;;; ============================================================================
;;;; ORCHESTRATOR-GRPC-SERVER Class
;;;; ============================================================================

(defclass orchestrator-grpc-server ()
  ((host
    :initarg :host
    :accessor server-host
    :initform "0.0.0.0"
    :type string
    :documentation "Hostname or IP address to bind the server to.

    Defaults to 0.0.0.0 (listen on all interfaces). In production, this
    might be set to a specific interface for security.")

   (port
    :initarg :port
    :accessor server-port
    :initform 50050
    :type (integer 1 65535)
    :documentation "Port number to listen on for gRPC connections.

    Defaults to 50050 (one less than default leaf port). Must be in the
    valid port range [1, 65535].")

   (server
    :accessor server-instance
    :initform nil
    :type (or null t)
    :documentation "Active gRPC server instance.

    NIL when server is not running. When running, this holds the gRPC
    server object (type depends on gRPC library used). Managed by
    START-SERVER/STOP-SERVER.")

   (orchestrator
    :initarg :orchestrator
    :accessor server-orchestrator
    :type (or null sw4rm-orchestrator.tree:swarm-node)
    :documentation "Reference to the SWARM-NODE orchestrator instance.

    This is the orchestrator that owns this server. When requests are
    received (e.g., route-envelope), they are delegated to this orchestrator.")

   (running-p
    :accessor server-running-p
    :initform nil
    :type boolean
    :documentation "Server running status flag.

    T if the server is running and accepting connections, NIL otherwise.
    Use GRPC-SERVER-RUNNING-P for public access.")

   (handlers
    :accessor server-handlers
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table mapping method names to handler functions.

    Keys are strings (method names like \"RegisterLeaf\", \"RouteEnvelope\").
    Values are functions (lambda (server request) ...).
    Populated during server initialization.")

   (registered-leaves
    :accessor server-registered-leaves
    :initform (make-hash-table :test 'equal)
    :type hash-table
    :documentation "Hash table tracking registered leaves.

    Keys are swarm IDs (strings). Values are LEAF-REGISTRATION structs.
    Updated by REGISTER-LEAF-CONNECTION and UNREGISTER-LEAF-CONNECTION.")

   (created-at
    :reader server-created-at
    :initform (get-universal-time)
    :type integer
    :documentation "Universal time when this server was created.

    Automatically set at construction time. Used for metrics and diagnostics."))

  (:documentation "gRPC server for accepting calls from Python sw4rm leaf instances.

  The ORCHESTRATOR-GRPC-SERVER implements the OrchestratorService gRPC interface,
  allowing Python leaves to:
    - Register themselves with the orchestrator
    - Request envelope routing across swarms
    - Send periodic heartbeats for health monitoring
    - Unregister on graceful shutdown

  Lifecycle:
    1. Create server: (make-grpc-server orchestrator :host \"0.0.0.0\" :port 50050)
    2. Start server: (start-server server)
    3. Accept requests (automatic, handled by gRPC layer)
    4. Stop server: (stop-server server :graceful t)

  Service Methods (OrchestratorService):
    - HANDLE-REGISTER-LEAF: Process leaf registration
    - HANDLE-UNREGISTER-LEAF: Process leaf unregistration
    - HANDLE-ROUTE-ENVELOPE: Route envelope across swarms
    - HANDLE-HEARTBEAT-STREAM: Process streaming heartbeats

  Connection Tracking:
    - REGISTER-LEAF-CONNECTION: Add leaf to registry
    - UNREGISTER-LEAF-CONNECTION: Remove leaf from registry
    - GET-REGISTERED-LEAF: Retrieve leaf by ID
    - *REGISTERED-LEAVES*: Global registry

  Examples:
    ;; Basic usage
    (let ((server (make-grpc-server orchestrator
                                    :host \"0.0.0.0\"
                                    :port 50050)))
      (start-server server)
      ;; ... server runs in background ...
      (stop-server server :graceful t))

    ;; With custom handlers
    (let ((server (make-grpc-server orchestrator)))
      (setf (gethash \"RouteEnvelope\" (server-handlers server))
            (lambda (server request)
              (custom-routing-logic server request)))
      (start-server server))

  See Also:
    START-SERVER, STOP-SERVER, HANDLE-REGISTER-LEAF, HANDLE-ROUTE-ENVELOPE"))

;;;; ============================================================================
;;;; Server Factory and Lifecycle
;;;; ============================================================================

(defun make-grpc-server (orchestrator &key (host "0.0.0.0") (port 50050))
  "Create a new ORCHESTRATOR-GRPC-SERVER instance.

  Args:
    orchestrator - SWARM-NODE instance that owns this server
    host - Hostname/IP to bind to (default: 0.0.0.0)
    port - Port to listen on (default: 50050)

  Returns:
    New ORCHESTRATOR-GRPC-SERVER instance (not yet started).

  Examples:
    (make-grpc-server orchestrator)
    => #<ORCHESTRATOR-GRPC-SERVER 0.0.0.0:50050>

    (make-grpc-server orchestrator :host \"localhost\" :port 9090)
    => #<ORCHESTRATOR-GRPC-SERVER localhost:9090>

  See Also:
    START-SERVER, STOP-SERVER"
  (declare (type sw4rm-orchestrator.tree:swarm-node orchestrator))

  (let ((server (make-instance 'orchestrator-grpc-server
                               :host host
                               :port port
                               :orchestrator orchestrator)))

    ;; Initialize default handlers
    (setf (gethash "RegisterLeaf" (server-handlers server))
          #'handle-register-leaf

          (gethash "UnregisterLeaf" (server-handlers server))
          #'handle-unregister-leaf

          (gethash "RouteEnvelope" (server-handlers server))
          #'handle-route-envelope

          (gethash "HeartbeatStream" (server-handlers server))
          #'handle-heartbeat-stream)

    server))

(defgeneric start-server (server)
  (:documentation "Start the gRPC server and begin accepting connections.

  Binds the server to the configured host:port and starts accepting
  gRPC connections from Python leaves. The server runs in the background
  and handles requests asynchronously.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance

  Returns:
    The server instance (for chaining).

  Signals:
    ERROR if server cannot bind to port or is already running.

  Side Effects:
    - Sets SERVER-INSTANCE to the gRPC server object
    - Sets SERVER-RUNNING-P to T
    - Begins accepting gRPC connections

  Examples:
    (start-server server)
    => #<ORCHESTRATOR-GRPC-SERVER 0.0.0.0:50050 RUNNING>

  See Also:
    STOP-SERVER, MAKE-GRPC-SERVER"))

(defmethod start-server ((server orchestrator-grpc-server))
  "Start the gRPC server and begin accepting connections."
  (when (server-running-p server)
    (error "Server is already running on ~A:~A"
           (server-host server)
           (server-port server)))

  ;; Placeholder: In production, start actual gRPC server
  ;; Example: (setf (server-instance server)
  ;;                (grpc:start-server
  ;;                  :host (server-host server)
  ;;                  :port (server-port server)
  ;;                  :services (list (make-orchestrator-service server))))

  (let ((address (format nil "~A:~A"
                         (server-host server)
                         (server-port server))))

    ;; Placeholder implementation
    (handler-case
        (progn
          ;; Simulate server creation
          ;; In actual implementation: server-obj = grpc.server(...)
          (let ((server-obj (make-hash-table)))  ; Placeholder
            (setf (server-instance server) server-obj
                  (server-running-p server) t)

            ;; Log server start
            (log:info "gRPC server started on ~A" address)
            (log:info "Accepting OrchestratorService calls")

            server))

      (error (e)
        ;; Server start failed
        (error "Failed to start gRPC server on ~A: ~A" address e)))))

(defgeneric stop-server (server &key graceful timeout)
  (:documentation "Stop the gRPC server and close all connections.

  Shuts down the gRPC server, optionally waiting for in-flight requests
  to complete. In graceful mode, the server waits up to timeout seconds
  for active requests to finish before forcing shutdown.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    graceful - If T, wait for in-flight requests (default: T)
    timeout - Maximum seconds to wait for graceful shutdown (default: 30)

  Returns:
    NIL

  Side Effects:
    - Closes all gRPC connections
    - Sets SERVER-INSTANCE to NIL
    - Sets SERVER-RUNNING-P to NIL
    - Clears registered leaves (optionally)

  Examples:
    (stop-server server :graceful t :timeout 60)
    => NIL

  See Also:
    START-SERVER, SERVER-RUNNING-P"))

(defmethod stop-server ((server orchestrator-grpc-server)
                         &key (graceful t) (timeout 30))
  "Stop the gRPC server and close all connections."
  (unless (server-running-p server)
    (warn "Server is not running")
    (return-from stop-server nil))

  ;; Placeholder: In production, stop actual gRPC server
  ;; Example: (grpc:stop-server (server-instance server)
  ;;                            :graceful graceful
  ;;                            :timeout timeout)

  (let ((address (format nil "~A:~A"
                         (server-host server)
                         (server-port server))))

    ;; Log shutdown
    (log:info "Stopping gRPC server on ~A (~A)"
              address
              (if graceful "graceful" "immediate"))

    ;; Simulate graceful shutdown
    (when graceful
      (log:info "Waiting up to ~As for in-flight requests" timeout)
      ;; In production, wait for active RPCs to complete
      (sleep 0.1))  ; Placeholder delay

    ;; Clear server state
    (setf (server-instance server) nil
          (server-running-p server) nil)

    ;; Log shutdown complete
    (log:info "gRPC server stopped")

    nil))

(defun grpc-server-running-p (server)
  "Check if gRPC server is running.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance

  Returns:
    T if server is running, NIL otherwise.

  Examples:
    (grpc-server-running-p server) => T

  See Also:
    START-SERVER, STOP-SERVER"
  (declare (type orchestrator-grpc-server server))
  (server-running-p server))

(defun grpc-server-address (server)
  "Get the server's bind address.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance

  Returns:
    String in format \"host:port\".

  Examples:
    (grpc-server-address server)
    => \"0.0.0.0:50050\"

  See Also:
    SERVER-HOST, SERVER-PORT"
  (declare (type orchestrator-grpc-server server))
  (format nil "~A:~A"
          (server-host server)
          (server-port server)))

;;;; ============================================================================
;;;; Registration Tracking (Global Registry)
;;;; ============================================================================

(defparameter *registered-leaves* (make-hash-table :test 'equal)
  "Global registry of registered leaves.

  This is a hash table mapping swarm IDs (strings) to LEAF-REGISTRATION structs.
  It tracks all leaves that have registered with the orchestrator.

  Note: Each server instance also maintains its own registry in
  SERVER-REGISTERED-LEAVES. This global registry is for convenience and
  cross-server queries.

  See Also:
    REGISTER-LEAF-CONNECTION, UNREGISTER-LEAF-CONNECTION, GET-REGISTERED-LEAF")

(defun register-leaf-connection (server leaf-registration)
  "Register a leaf connection in the server's registry.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    leaf-registration - LEAF-REGISTRATION struct

  Returns:
    The LEAF-REGISTRATION struct.

  Side Effects:
    - Adds leaf to SERVER-REGISTERED-LEAVES
    - Adds leaf to *REGISTERED-LEAVES* global registry
    - Logs registration

  Examples:
    (register-leaf-connection server registration)
    => #<LEAF-REGISTRATION swarm-id: \"leaf-a\">

  See Also:
    UNREGISTER-LEAF-CONNECTION, GET-REGISTERED-LEAF"
  (declare (type orchestrator-grpc-server server)
           (type leaf-registration leaf-registration))

  (let ((swarm-id (leaf-registration-swarm-id leaf-registration)))
    ;; Add to server registry
    (setf (gethash swarm-id (server-registered-leaves server))
          leaf-registration)

    ;; Add to global registry
    (setf (gethash swarm-id *registered-leaves*)
          leaf-registration)

    ;; Log registration
    (log:info "Registered leaf ~A (~A:~A)"
              swarm-id
              (leaf-registration-host leaf-registration)
              (leaf-registration-port leaf-registration))

    leaf-registration))

(defun unregister-leaf-connection (server swarm-id)
  "Unregister a leaf connection from the server's registry.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    swarm-id - Swarm ID string of the leaf to unregister

  Returns:
    The LEAF-REGISTRATION struct that was removed, or NIL if not found.

  Side Effects:
    - Removes leaf from SERVER-REGISTERED-LEAVES
    - Removes leaf from *REGISTERED-LEAVES* global registry
    - Logs unregistration

  Examples:
    (unregister-leaf-connection server \"leaf-a\")
    => #<LEAF-REGISTRATION swarm-id: \"leaf-a\">

  See Also:
    REGISTER-LEAF-CONNECTION, GET-REGISTERED-LEAF"
  (declare (type orchestrator-grpc-server server)
           (type string swarm-id))

  (let ((registration (gethash swarm-id (server-registered-leaves server))))
    ;; Remove from server registry
    (remhash swarm-id (server-registered-leaves server))

    ;; Remove from global registry
    (remhash swarm-id *registered-leaves*)

    ;; Log unregistration
    (when registration
      (log:info "Unregistered leaf ~A" swarm-id))

    registration))

(defun get-registered-leaf (server swarm-id)
  "Retrieve a registered leaf by ID.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    swarm-id - Swarm ID string

  Returns:
    LEAF-REGISTRATION struct, or NIL if not registered.

  Examples:
    (get-registered-leaf server \"leaf-a\")
    => #<LEAF-REGISTRATION swarm-id: \"leaf-a\">

  See Also:
    REGISTER-LEAF-CONNECTION, UNREGISTER-LEAF-CONNECTION"
  (declare (type orchestrator-grpc-server server)
           (type string swarm-id))
  (gethash swarm-id (server-registered-leaves server)))

;;;; ============================================================================
;;;; OrchestratorService Implementation
;;;; ============================================================================

(defgeneric handle-register-leaf (server request)
  (:documentation "Handle RegisterLeaf RPC from Python leaf.

  Processes a leaf registration request. If registration succeeds, the
  leaf is added to the orchestrator's routing table and can begin
  receiving envelopes.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    request - LEAF-REGISTRATION struct (or protobuf message)

  Returns:
    REGISTRATION-RESPONSE struct.

  Side Effects:
    - Adds leaf to registered leaves registry
    - May update orchestrator's routing table
    - Logs registration

  Examples:
    (handle-register-leaf server registration)
    => #<REGISTRATION-RESPONSE success: T assigned-id: \"leaf-a\">

  See Also:
    HANDLE-UNREGISTER-LEAF, REGISTER-LEAF-CONNECTION"))

(defmethod handle-register-leaf ((server orchestrator-grpc-server)
                                  (request leaf-registration))
  "Handle RegisterLeaf RPC from Python leaf."
  (let ((swarm-id (leaf-registration-swarm-id request)))

    ;; Validate request
    (unless swarm-id
      (return-from handle-register-leaf
        (make-registration-response
          :success nil
          :error-message "Missing swarm-id in registration request")))

    ;; Check for duplicate registration
    (when (get-registered-leaf server swarm-id)
      (log:warn "Leaf ~A is already registered (re-registration)" swarm-id))

    ;; Register the leaf
    (register-leaf-connection server request)

    ;; Register with orchestrator's routing table
    ;; (In production, this would call orchestrator.register-child or similar)
    ;; (sw4rm-orchestrator.tree:register-child
    ;;   (server-orchestrator server)
    ;;   (make-instance 'sw4rm-orchestrator.tree:swarm-leaf
    ;;                  :id swarm-id
    ;;                  :grpc-client (make-instance 'leaf-grpc-client
    ;;                                              :swarm-id swarm-id
    ;;                                              :host (leaf-registration-host request)
    ;;                                              :port (leaf-registration-port request))))

    ;; Return success response
    (make-registration-response
      :success t
      :assigned-id swarm-id
      :error-message nil)))

(defgeneric handle-unregister-leaf (server request)
  (:documentation "Handle UnregisterLeaf RPC from Python leaf.

  Processes a leaf unregistration request. The leaf is removed from
  the orchestrator's routing table and will no longer receive envelopes.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    request - Hash-table or struct with :swarm-id

  Returns:
    Hash-table with :success and :message fields.

  Side Effects:
    - Removes leaf from registered leaves registry
    - May update orchestrator's routing table
    - Logs unregistration

  Examples:
    (handle-unregister-leaf server request)
    => #<HASH-TABLE :SUCCESS T :MESSAGE \"Unregistered\">

  See Also:
    HANDLE-REGISTER-LEAF, UNREGISTER-LEAF-CONNECTION"))

(defmethod handle-unregister-leaf ((server orchestrator-grpc-server) request)
  "Handle UnregisterLeaf RPC from Python leaf."
  (let* ((swarm-id (if (hash-table-p request)
                       (gethash "swarm_id" request)
                       (getf request :swarm-id)))
         (response (make-hash-table :test 'equal)))

    ;; Validate request
    (unless swarm-id
      (setf (gethash "success" response) nil
            (gethash "message" response) "Missing swarm-id in request")
      (return-from handle-unregister-leaf response))

    ;; Check if leaf is registered
    (unless (get-registered-leaf server swarm-id)
      (setf (gethash "success" response) nil
            (gethash "message" response)
            (format nil "Leaf ~A is not registered" swarm-id))
      (return-from handle-unregister-leaf response))

    ;; Unregister the leaf
    (unregister-leaf-connection server swarm-id)

    ;; Unregister from orchestrator's routing table
    ;; (In production, this would call orchestrator.unregister-child or similar)
    ;; (sw4rm-orchestrator.tree:unregister-child
    ;;   (server-orchestrator server)
    ;;   swarm-id)

    ;; Return success response
    (setf (gethash "success" response) t
          (gethash "message" response)
          (format nil "Leaf ~A unregistered successfully" swarm-id))

    response))

(defgeneric handle-route-envelope (server request)
  (:documentation "Handle RouteEnvelope RPC from Python leaf.

  Processes a routing request from a leaf. The envelope is forwarded
  through the orchestrator's routing infrastructure to reach its target.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    request - Hash-table or protobuf message with envelope data

  Returns:
    Hash-table with :success, :routing-decision, and :message fields.

  Side Effects:
    - Routes envelope through orchestrator
    - May deliver envelope to another leaf
    - May queue envelope for later delivery
    - Logs routing decision

  Examples:
    (handle-route-envelope server request)
    => #<HASH-TABLE :SUCCESS T :ROUTING-DECISION :CHILD>

  See Also:
    SW4RM-ORCHESTRATOR.TREE:ROUTE-ENVELOPE, HANDLE-REGISTER-LEAF"))

(defmethod handle-route-envelope ((server orchestrator-grpc-server) request)
  "Handle RouteEnvelope RPC from Python leaf."
  (let ((response (make-hash-table :test 'equal)))

    ;; Extract envelope from request
    ;; In production, this would deserialize protobuf
    (let ((envelope (if (hash-table-p request)
                        (proto-to-envelope request)
                        request)))

      ;; Validate envelope
      (handler-case
          (progn
            ;; Route envelope through orchestrator
            ;; (In production, this would call:)
            ;; (sw4rm-orchestrator.tree:route-envelope
            ;;   (server-orchestrator server)
            ;;   envelope)

            ;; Placeholder: Log routing
            (log:info "Routing envelope ~A from ~A to ~A"
                      (sw4rm-orchestrator.envelope:envelope-id envelope)
                      (sw4rm-orchestrator.envelope:envelope-source-swarm envelope)
                      (sw4rm-orchestrator.envelope:envelope-target-swarm envelope))

            ;; Return success response
            (setf (gethash "success" response) t
                  (gethash "routing_decision" response) "routed"
                  (gethash "message" response) "Envelope routed successfully"))

        (sw4rm-orchestrator.errors:routing-error (e)
          ;; Routing failed
          (setf (gethash "success" response) nil
                (gethash "routing_decision" response) "failed"
                (gethash "message" response)
                (format nil "Routing error: ~A" e)))

        (error (e)
          ;; General error
          (setf (gethash "success" response) nil
                (gethash "routing_decision" response) "error"
                (gethash "message" response)
                (format nil "Error: ~A" e)))))

    response))

(defgeneric handle-heartbeat-stream (server stream)
  (:documentation "Handle HeartbeatStream RPC from Python leaf.

  Processes a streaming heartbeat connection from a leaf. The server
  reads heartbeat messages from the stream and sends acknowledgements.

  This is a bidirectional streaming RPC where:
    - Leaf sends HEARTBEAT messages periodically
    - Server sends HEARTBEAT-ACK messages in response

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    stream - gRPC bidirectional stream

  Returns:
    NIL (runs until stream is closed).

  Side Effects:
    - Updates leaf health status based on heartbeats
    - May trigger alerts if heartbeats stop
    - Logs heartbeat activity

  Examples:
    ;; This is called automatically by the gRPC framework
    (handle-heartbeat-stream server stream)

  See Also:
    HEARTBEAT, HEARTBEAT-ACK"))

(defmethod handle-heartbeat-stream ((server orchestrator-grpc-server) stream)
  "Handle HeartbeatStream RPC from Python leaf."
  ;; Placeholder: In production, this would read from gRPC stream
  ;; Example:
  ;;   (loop
  ;;     (let ((heartbeat (grpc:stream-read stream)))
  ;;       (unless heartbeat (return))
  ;;       (process-heartbeat server heartbeat)
  ;;       (grpc:stream-write stream (make-heartbeat-ack))))

  (log:info "Heartbeat stream established")

  ;; Simulate heartbeat processing
  ;; In production, this would loop reading from stream until closed
  (dotimes (i 3)  ; Simulate 3 heartbeats
    (let ((heartbeat (make-heartbeat
                       :swarm-id "leaf-a"
                       :timestamp (get-universal-time)
                       :metrics-plist '(:cpu 0.5 :memory 1024)
                       :status :healthy)))

      ;; Process heartbeat
      (log:info "Received heartbeat from ~A (status: ~A)"
                (heartbeat-swarm-id heartbeat)
                (heartbeat-status heartbeat))

      ;; Send acknowledgement
      (let ((ack (make-heartbeat-ack
                   :acknowledged t
                   :timestamp (get-universal-time)
                   :instructions nil)))

        (log:info "Sent heartbeat ack")

        ;; In production: (grpc:stream-write stream (heartbeat-ack-to-proto ack))
        )))

  (log:info "Heartbeat stream closed")
  nil)

;;;; ============================================================================
;;;; Serialization - Protobuf Conversion
;;;; ============================================================================

(defun heartbeat-to-proto (heartbeat)
  "Convert Lisp HEARTBEAT to protobuf message.

  Args:
    heartbeat - HEARTBEAT struct

  Returns:
    Protobuf message object (hash-table in placeholder).

  See Also:
    PROTO-TO-HEARTBEAT"
  (declare (type heartbeat heartbeat))

  (let ((proto (make-hash-table :test 'equal)))
    (setf (gethash "swarm_id" proto)
          (heartbeat-swarm-id heartbeat)

          (gethash "timestamp" proto)
          (heartbeat-timestamp heartbeat)

          (gethash "metrics" proto)
          (heartbeat-metrics-plist heartbeat)

          (gethash "status" proto)
          (symbol-name (heartbeat-status heartbeat)))

    proto))

(defun proto-to-heartbeat (proto)
  "Convert protobuf message to Lisp HEARTBEAT.

  Args:
    proto - Protobuf message object (hash-table in placeholder)

  Returns:
    HEARTBEAT struct.

  See Also:
    HEARTBEAT-TO-PROTO"
  (make-heartbeat
    :swarm-id (gethash "swarm_id" proto)
    :timestamp (gethash "timestamp" proto)
    :metrics-plist (gethash "metrics" proto)
    :status (intern (string-upcase (gethash "status" proto)) :keyword)))

;;;; ============================================================================
;;;; Handler Registration
;;;; ============================================================================

(defun register-routing-handler (server handler-fn)
  "Register a custom handler for RouteEnvelope RPC.

  Allows overriding the default routing handler with custom logic.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    handler-fn - Function of signature (lambda (server request) ...)

  Returns:
    The handler function.

  Examples:
    (register-routing-handler server
      (lambda (server request)
        (custom-routing-logic server request)))

  See Also:
    REGISTER-LEAF-STATUS-HANDLER, REGISTER-HEARTBEAT-HANDLER"
  (declare (type orchestrator-grpc-server server)
           (type function handler-fn))
  (setf (gethash "RouteEnvelope" (server-handlers server))
        handler-fn))

(defun register-leaf-status-handler (server handler-fn)
  "Register a custom handler for GetLeafStatus RPC.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    handler-fn - Function of signature (lambda (server request) ...)

  Returns:
    The handler function.

  See Also:
    REGISTER-ROUTING-HANDLER, REGISTER-HEARTBEAT-HANDLER"
  (declare (type orchestrator-grpc-server server)
           (type function handler-fn))
  (setf (gethash "GetLeafStatus" (server-handlers server))
        handler-fn))

(defun register-heartbeat-handler (server handler-fn)
  "Register a custom handler for HeartbeatStream RPC.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance
    handler-fn - Function of signature (lambda (server stream) ...)

  Returns:
    The handler function.

  See Also:
    REGISTER-ROUTING-HANDLER, REGISTER-LEAF-STATUS-HANDLER"
  (declare (type orchestrator-grpc-server server)
           (type function handler-fn))
  (setf (gethash "HeartbeatStream" (server-handlers server))
        handler-fn))

;;;; ============================================================================
;;;; Utility Functions
;;;; ============================================================================

(defun list-registered-leaves (server)
  "List all registered leaves.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance

  Returns:
    List of LEAF-REGISTRATION structs.

  Examples:
    (list-registered-leaves server)
    => (#<LEAF-REGISTRATION swarm-id: \"leaf-a\">
        #<LEAF-REGISTRATION swarm-id: \"leaf-b\">)

  See Also:
    GET-REGISTERED-LEAF, REGISTER-LEAF-CONNECTION"
  (declare (type orchestrator-grpc-server server))
  (loop for registration being the hash-values of (server-registered-leaves server)
        collect registration))

(defun count-registered-leaves (server)
  "Count number of registered leaves.

  Args:
    server - ORCHESTRATOR-GRPC-SERVER instance

  Returns:
    Integer count of registered leaves.

  Examples:
    (count-registered-leaves server)
    => 5

  See Also:
    LIST-REGISTERED-LEAVES"
  (declare (type orchestrator-grpc-server server))
  (hash-table-count (server-registered-leaves server)))

;;;; ============================================================================
;;;; PRINT-OBJECT Method
;;;; ============================================================================

(defmethod print-object ((server orchestrator-grpc-server) stream)
  "Print ORCHESTRATOR-GRPC-SERVER in readable format.

  Format:
    #<ORCHESTRATOR-GRPC-SERVER host:port STATUS>

  Examples:
    #<ORCHESTRATOR-GRPC-SERVER 0.0.0.0:50050 RUNNING>
    #<ORCHESTRATOR-GRPC-SERVER localhost:9090 STOPPED>"
  (print-unreadable-object (server stream :type t :identity nil)
    (format stream "~A ~A"
            (grpc-server-address server)
            (if (server-running-p server) "RUNNING" "STOPPED"))))

;;;; ============================================================================
;;;; End of file
;;;; ============================================================================
