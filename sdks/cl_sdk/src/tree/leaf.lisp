;;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; Base: 10 -*-
;;;;
;;;; tree/leaf.lisp
;;;;
;;;; Concrete implementation of SWARM-LEAF operations for the SW4RM orchestrator.
;;;;
;;;; This module implements the leaf-specific routing and connection management
;;;; logic. A SWARM-LEAF wraps a Python sw4rm instance running in a separate
;;;; process and communicates via gRPC.
;;;;
;;;; Key operations:
;;;;   - ROUTE-ENVELOPE: Route messages to/through this leaf
;;;;   - RECEIVE-ENVELOPE: Deliver messages to Python sw4rm via gRPC
;;;;   - Connection management: connect, disconnect, health monitoring
;;;;   - Heartbeat tracking for liveness detection
;;;;
;;;; Routing behavior for leaves:
;;;;   - If target matches this leaf's ID: deliver locally via gRPC
;;;;   - Otherwise: route to parent (upward routing)
;;;;   - Leaves cannot route to siblings (no horizontal routing)
;;;;
;;;; Architecture:
;;;;   SWARM-LEAF instances maintain:
;;;;     - gRPC connection to Python sw4rm instance
;;;;     - Heartbeat timestamp for health monitoring
;;;;     - Agent registry (list of agents in this leaf)
;;;;     - Capability metadata
;;;;
;;;; Version: 0.6.0
;;;; Author: SW4RM Platform Team
;;;; License: Apache 2.0

(in-package :sw4rm-orchestrator.tree)

;;;; ============================================================================
;;;; Error Conditions for Leaf Operations
;;;; ============================================================================

(define-condition leaf-connection-error (error)
  ((leaf-id
    :initarg :leaf-id
    :reader leaf-connection-error-leaf-id
    :documentation "ID of the leaf that failed to connect.")
   (reason
    :initarg :reason
    :reader leaf-connection-error-reason
    :documentation "Human-readable reason for the connection failure."))
  (:documentation "Error signaled when a leaf connection fails.

  This condition is signaled when:
    - gRPC connection cannot be established
    - Connection is lost unexpectedly
    - Connection timeout occurs

  Handlers can invoke restarts to:
    - RETRY-CONNECTION: Attempt to reconnect
    - USE-CACHED-CONNECTION: Use stale connection if available
    - SKIP-LEAF: Mark leaf as unavailable and continue"))

(define-condition leaf-delivery-error (error)
  ((leaf-id
    :initarg :leaf-id
    :reader leaf-delivery-error-leaf-id
    :documentation "ID of the leaf that failed to deliver.")
   (envelope-id
    :initarg :envelope-id
    :reader leaf-delivery-error-envelope-id
    :documentation "ID of the envelope that failed to deliver.")
   (reason
    :initarg :reason
    :reader leaf-delivery-error-reason
    :documentation "Human-readable reason for the delivery failure."))
  (:documentation "Error signaled when envelope delivery to leaf fails.

  This condition is signaled when:
    - gRPC call fails (network error, timeout)
    - Leaf rejects the envelope
    - Serialization/deserialization fails

  Handlers can invoke restarts to:
    - RETRY-DELIVERY: Attempt redelivery
    - QUEUE-FOR-RETRY: Queue envelope for later delivery
    - DEAD-LETTER: Send to dead-letter queue
    - DROP-ENVELOPE: Discard envelope"))

;;;; ============================================================================
;;;; ROUTE-ENVELOPE for SWARM-LEAF
;;;; ============================================================================

(defmethod route-envelope ((leaf swarm-leaf) envelope)
  "Route envelope through this leaf node.

  Routing decision logic:
    1. Check if target-swarm matches this leaf's ID
       - If YES: deliver locally via RECEIVE-ENVELOPE
       - If NO: proceed to step 2

    2. Check if leaf has a parent
       - If YES: route to parent (upward routing)
       - If NO: reject (orphan leaf, no route available)

  Args:
    leaf: SWARM-LEAF instance
    envelope: CROSS-SWARM-ENVELOPE to route

  Returns:
    ROUTING-RESULT with decision and target.

  Side Effects:
    - Increments hop count in envelope
    - Adds leaf ID to envelope path
    - Records routing metrics

  Raises:
    MAX-HOPS-EXCEEDED if hop limit reached
    ENVELOPE-EXPIRED if deadline passed

  Examples:
    ;; Local delivery
    (let* ((leaf (make-instance 'swarm-leaf :id \"leaf-a\"))
           (env (make-cross-swarm-envelope :target-swarm \"leaf-a\")))
      (route-envelope leaf env))
    => #<ROUTING-RESULT decision=:LOCAL ...>

    ;; Route to parent
    (let* ((parent (make-instance 'swarm-node :id \"root\"))
           (leaf (make-instance 'swarm-leaf :id \"leaf-a\" :parent parent))
           (env (make-cross-swarm-envelope :target-swarm \"leaf-b\")))
      (route-envelope leaf env))
    => #<ROUTING-RESULT decision=:PARENT ...>

  See Also:
    RECEIVE-ENVELOPE, ROUTING-RESULT, CROSS-SWARM-ENVELOPE"
  ;; Import envelope utilities
  (let ((target-swarm (envelope-target-swarm envelope))
        (leaf-id (swarm-id leaf)))

    ;; Check hop limit before routing
    (when (envelope-hop-limit-exceeded-p envelope)
      (error "Hop limit exceeded for envelope ~A (hops: ~A, max: ~A)"
             (envelope-id envelope)
             (envelope-hop-count envelope)
             (envelope-max-hops envelope)))

    ;; Check deadline before routing
    (when (envelope-expired-p envelope)
      (error "Envelope ~A expired (deadline: ~A, now: ~A)"
             (envelope-id envelope)
             (envelope-deadline envelope)
             (get-universal-time)))

    ;; Update path tracking
    (envelope-add-to-path envelope leaf-id)
    (envelope-increment-hop-count envelope)

    ;; Record routing attempt
    (record-metric (node-metrics leaf) :envelopes-routed 1 :type :counter)

    (cond
      ;; Case 1: Target is this leaf - deliver locally
      ((and target-swarm (string= target-swarm leaf-id))
       (record-metric (node-metrics leaf) :local-deliveries 1 :type :counter)
       (receive-envelope leaf envelope)
       (make-routing-result
        :decision :local
        :target leaf-id
        :reason "Target swarm matches leaf ID"))

      ;; Case 2: Target is elsewhere and we have a parent - route upward
      ((parent-node leaf)
       (record-metric (node-metrics leaf) :parent-routes 1 :type :counter)
       (make-routing-result
        :decision :parent
        :target (swarm-id (parent-node leaf))
        :reason "Routing to parent (upward routing)"))

      ;; Case 3: No parent and not local - reject
      (t
       (record-metric (node-metrics leaf) :rejected-routes 1 :type :counter)
       (make-routing-result
        :decision :reject
        :target nil
        :reason (format nil "No route to ~A (orphan leaf)" target-swarm))))))

;;;; ============================================================================
;;;; RECEIVE-ENVELOPE for SWARM-LEAF
;;;; ============================================================================

(defmethod receive-envelope ((leaf swarm-leaf) envelope)
  "Receive envelope at this leaf (local delivery to Python sw4rm).

  This method is called when an envelope's target-swarm matches this leaf's ID.
  The envelope is delivered to the Python sw4rm instance via gRPC.

  Delivery process:
    1. Log receipt of envelope
    2. Verify connection status
    3. Convert envelope to protobuf format
    4. Send via gRPC channel
    5. Wait for acknowledgment
    6. Return delivery result

  Args:
    leaf: SWARM-LEAF instance
    envelope: CROSS-SWARM-ENVELOPE to receive

  Returns:
    Delivery acknowledgment (structure depends on gRPC module).

  Side Effects:
    - Records delivery metrics
    - Updates last-activity timestamp
    - Logs delivery event

  Raises:
    LEAF-CONNECTION-ERROR if not connected to Python sw4rm
    LEAF-DELIVERY-ERROR if gRPC delivery fails

  Examples:
    (let* ((leaf (make-instance 'swarm-leaf :id \"leaf-a\"))
           (env (make-cross-swarm-envelope
                  :target-swarm \"leaf-a\"
                  :recipient \"agent-1\"
                  :payload '(:message \"hello\"))))
      (receive-envelope leaf env))
    => #<DELIVERY-ACK ...>

  See Also:
    DELIVER-TO-PYTHON-SWARM, ROUTE-ENVELOPE"
  (let ((leaf-id (swarm-id leaf))
        (env-id (envelope-id envelope)))

    ;; Log receipt
    (log:info "[LEAF ~A] Receiving envelope ~A" leaf-id env-id)

    ;; Record metric
    (record-metric (node-metrics leaf) :envelopes-received 1 :type :counter)

    ;; Deliver to Python sw4rm via gRPC
    (handler-case
        (deliver-to-python-swarm leaf envelope)

      (error (e)
        ;; Record failure
        (record-metric (node-metrics leaf) :delivery-failures 1 :type :counter)

        ;; Re-signal as leaf-delivery-error
        (error 'leaf-delivery-error
               :leaf-id leaf-id
               :envelope-id env-id
               :reason (format nil "Delivery failed: ~A" e))))))

;;;; ============================================================================
;;;; Python sw4rm Delivery (gRPC Integration)
;;;; ============================================================================

(defun deliver-to-python-swarm (leaf envelope)
  "Deliver envelope to Python sw4rm instance via gRPC.

  This is the low-level delivery function that:
    1. Checks connection status
    2. Converts envelope to protobuf format
    3. Sends via gRPC channel
    4. Handles errors with restarts

  Args:
    leaf: SWARM-LEAF instance
    envelope: CROSS-SWARM-ENVELOPE to deliver

  Returns:
    Delivery acknowledgment from Python sw4rm.

  Raises:
    LEAF-CONNECTION-ERROR if not connected
    LEAF-DELIVERY-ERROR if gRPC call fails

  Restarts:
    RETRY-DELIVERY: Retry the delivery operation
    QUEUE-FOR-RETRY: Queue envelope for later delivery
    DROP-ENVELOPE: Discard envelope without delivery

  Notes:
    This is a placeholder implementation. The actual gRPC integration
    requires the sw4rm-orchestrator.grpc package to be implemented.

    The gRPC module will provide:
      - ENVELOPE-TO-PROTO: Convert Lisp envelope to protobuf
      - GRPC-CALL: Make synchronous gRPC call
      - GRPC-CALL-ASYNC: Make asynchronous gRPC call

  TODO:
    - Implement actual gRPC call once grpc module is ready
    - Add retry logic with exponential backoff
    - Add circuit breaker for failing connections
    - Add async delivery for high-throughput scenarios

  See Also:
    RECEIVE-ENVELOPE, CONNECT-LEAF, LEAF-CONNECTED-P"
  (restart-case
      (progn
        ;; Check connection status
        (unless (leaf-connected-p leaf)
          (error 'leaf-connection-error
                 :leaf-id (swarm-id leaf)
                 :reason "Leaf not connected to Python sw4rm"))

        ;; Log delivery attempt
        (log:info "[LEAF ~A] Delivering envelope ~A to Python sw4rm"
                  (swarm-id leaf)
                  (envelope-id envelope))

        ;; TODO: Convert envelope to proto format
        ;; (let ((proto-envelope (envelope-to-proto envelope)))
        ;;   ...)

        ;; TODO: Send via gRPC channel
        ;; (grpc-call (grpc-channel leaf) "DeliverEnvelope" proto-envelope)

        ;; Placeholder: simulate successful delivery
        (log:info "[LEAF ~A] Successfully delivered envelope ~A (SIMULATED)"
                  (swarm-id leaf)
                  (envelope-id envelope))

        ;; Return acknowledgment (placeholder)
        (list :status "delivered"
              :envelope-id (envelope-id envelope)
              :leaf-id (swarm-id leaf)
              :timestamp (get-universal-time)))

    (retry-delivery ()
      :report "Retry the delivery operation"
      (deliver-to-python-swarm leaf envelope))

    (queue-for-retry ()
      :report "Queue envelope for later delivery"
      (log:info "[LEAF ~A] Queuing envelope ~A for retry"
                (swarm-id leaf)
                (envelope-id envelope))
      ;; TODO: Implement retry queue
      (list :status "queued"
            :envelope-id (envelope-id envelope)))

    (drop-envelope ()
      :report "Discard envelope without delivery"
      (log:warn "[LEAF ~A] Dropping envelope ~A"
                (swarm-id leaf)
                (envelope-id envelope))
      (list :status "dropped"
            :envelope-id (envelope-id envelope)))))

;;;; ============================================================================
;;;; Connection Management
;;;; ============================================================================

(defun connect-leaf (leaf)
  "Establish gRPC connection to Python sw4rm instance.

  This operation:
    1. Creates gRPC channel to leaf's host:port
    2. Initializes service stubs (scheduler, router, registry)
    3. Starts heartbeat stream
    4. Sets connection status
    5. Updates node status to :READY

  Args:
    leaf: SWARM-LEAF instance

  Returns:
    T on success, NIL on failure.

  Side Effects:
    - Creates gRPC channel and stores in GRPC-CHANNEL slot
    - Creates gRPC client wrapper and stores in LEAF-GRPC-CLIENT slot
    - Updates NODE-STATUS to :READY
    - Starts heartbeat monitoring

  Raises:
    LEAF-CONNECTION-ERROR if connection fails

  Examples:
    (let ((leaf (make-instance 'swarm-leaf
                               :id \"leaf-a\"
                               :host \"localhost\"
                               :port 50051)))
      (connect-leaf leaf))
    => T

  Notes:
    This is a placeholder implementation. Actual gRPC connection logic
    requires the sw4rm-orchestrator.grpc package.

  TODO:
    - Implement actual gRPC channel creation
    - Add connection timeout
    - Add TLS support for secure connections
    - Add retry logic with exponential backoff

  See Also:
    DISCONNECT-LEAF, LEAF-CONNECTED-P, RECONNECT-LEAF"
  (let ((leaf-id (swarm-id leaf))
        (host (leaf-host leaf))
        (port (leaf-port leaf)))

    (log:info "[LEAF ~A] Connecting to Python sw4rm at ~A:~A"
              leaf-id host port)

    (handler-case
        (progn
          ;; TODO: Create gRPC channel
          ;; (setf (grpc-channel leaf)
          ;;       (grpc:create-channel (format nil "~A:~A" host port)))

          ;; TODO: Create gRPC client wrapper
          ;; (setf (leaf-grpc-client leaf)
          ;;       (make-instance 'leaf-grpc-client
          ;;                      :channel (grpc-channel leaf)))

          ;; Placeholder: simulate successful connection
          (log:info "[LEAF ~A] Successfully connected (SIMULATED)" leaf-id)

          ;; Update status
          (setf (node-status leaf) :ready)

          ;; Initialize heartbeat
          (update-heartbeat leaf)

          t)

      (error (e)
        (setf (node-status leaf) :degraded)
        (error 'leaf-connection-error
               :leaf-id leaf-id
               :reason (format nil "Connection failed: ~A" e))))))

(defun disconnect-leaf (leaf)
  "Close gRPC connection to Python sw4rm instance.

  This operation:
    1. Stops heartbeat stream
    2. Closes gRPC channel
    3. Clears service stubs
    4. Updates node status to :SHUTTING-DOWN

  Args:
    leaf: SWARM-LEAF instance

  Returns:
    T on success.

  Side Effects:
    - Closes gRPC channel
    - Clears GRPC-CHANNEL slot
    - Clears LEAF-GRPC-CLIENT slot
    - Updates NODE-STATUS to :SHUTTING-DOWN

  Examples:
    (disconnect-leaf leaf)
    => T

  See Also:
    CONNECT-LEAF, LEAF-CONNECTED-P"
  (let ((leaf-id (swarm-id leaf)))

    (log:info "[LEAF ~A] Disconnecting from Python sw4rm" leaf-id)

    ;; TODO: Close gRPC channel
    ;; (when (grpc-channel leaf)
    ;;   (grpc:close-channel (grpc-channel leaf)))

    ;; Clear connection state
    (setf (grpc-channel leaf) nil)
    (setf (leaf-grpc-client leaf) nil)

    ;; Update status
    (setf (node-status leaf) :shutting-down)

    (log:info "[LEAF ~A] Disconnected" leaf-id)
    t))

(defun leaf-connected-p (leaf)
  "Check if leaf is connected to Python sw4rm instance.

  Args:
    leaf: SWARM-LEAF instance

  Returns:
    T if connected, NIL otherwise.

  Notes:
    Checks for presence of gRPC channel. Does not verify channel health.
    For health verification, use LEAF-HEALTHY-P which checks heartbeat.

  Examples:
    (leaf-connected-p leaf)
    => T

  See Also:
    CONNECT-LEAF, DISCONNECT-LEAF, LEAF-HEALTHY-P"
  (not (null (grpc-channel leaf))))

(defun reconnect-leaf (leaf)
  "Reconnect to Python sw4rm instance.

  This is a convenience function that disconnects and reconnects.
  Useful for recovering from connection errors.

  Args:
    leaf: SWARM-LEAF instance

  Returns:
    T on success.

  Examples:
    (reconnect-leaf leaf)
    => T

  See Also:
    CONNECT-LEAF, DISCONNECT-LEAF"
  (when (leaf-connected-p leaf)
    (disconnect-leaf leaf))
  (connect-leaf leaf))

;;;; ============================================================================
;;;; Heartbeat Management
;;;; ============================================================================

(defun update-heartbeat (leaf)
  "Update the last-heartbeat timestamp for this leaf.

  Called when:
    - Heartbeat message received from Python sw4rm
    - Successful delivery completes
    - Connection established

  Args:
    leaf: SWARM-LEAF instance

  Returns:
    The new heartbeat timestamp (universal-time).

  Side Effects:
    - Updates LEAF-LAST-HEARTBEAT slot

  Examples:
    (update-heartbeat leaf)
    => 3912345678  ; universal-time

  See Also:
    LEAF-HEALTHY-P, LEAF-STALE-P"
  (setf (leaf-last-heartbeat leaf) (get-universal-time)))

(defun leaf-healthy-p (leaf &optional (threshold 30))
  "Check if leaf is healthy (heartbeat is fresh).

  A leaf is considered healthy if:
    1. It has received at least one heartbeat
    2. The last heartbeat was within threshold seconds

  Args:
    leaf: SWARM-LEAF instance
    threshold: Maximum age of heartbeat in seconds (default 30)

  Returns:
    T if healthy, NIL otherwise.

  Examples:
    (leaf-healthy-p leaf)
    => T

    (leaf-healthy-p leaf 10)  ; Strict 10-second threshold
    => NIL

  See Also:
    LEAF-STALE-P, UPDATE-HEARTBEAT"
  (let ((last-hb (leaf-last-heartbeat leaf)))
    (and last-hb
         (<= (- (get-universal-time) last-hb) threshold))))

(defun leaf-stale-p (leaf &optional (threshold 60))
  "Check if leaf heartbeat is stale (too old).

  This is the inverse of LEAF-HEALTHY-P with a more generous threshold.
  Used to detect leaves that may have crashed or disconnected.

  Args:
    leaf: SWARM-LEAF instance
    threshold: Maximum age of heartbeat in seconds (default 60)

  Returns:
    T if stale, NIL otherwise.

  Examples:
    (leaf-stale-p leaf)
    => NIL

    (leaf-stale-p leaf 300)  ; 5-minute threshold
    => T

  See Also:
    LEAF-HEALTHY-P, UPDATE-HEARTBEAT"
  (not (leaf-healthy-p leaf threshold)))

;;;; ============================================================================
;;;; :AROUND Methods for Metrics and Tracing
;;;; ============================================================================

(defmethod route-envelope :around ((leaf swarm-leaf) envelope)
  "Metrics and tracing wrapper for leaf routing.

  Records:
    - Routing latency (histogram)
    - Routing attempts (counter)
    - Routing decision distribution (by decision type)

  Also adds trace logging for debugging."
  (let ((start-time (get-internal-real-time))
        (leaf-id (swarm-id leaf))
        (env-id (envelope-id envelope)))

    ;; Trace: routing start
    (log:debug "Routing envelope ~A through leaf ~A"
               env-id leaf-id)

    ;; Call primary method
    (let ((result (call-next-method)))

      ;; Calculate latency
      (let ((latency-ms (/ (* (- (get-internal-real-time) start-time) 1000)
                           internal-time-units-per-second)))

        ;; Record latency
        (record-metric (node-metrics leaf) :route-latency-ms latency-ms
                       :type :histogram)

        ;; Trace: routing complete
        (log:debug "Routed envelope ~A via leaf ~A: decision=~A latency=~Ams"
                   env-id leaf-id
                   (routing-result-decision result)
                   latency-ms))

      ;; Return result
      result)))

(defmethod receive-envelope :around ((leaf swarm-leaf) envelope)
  "Metrics and tracing wrapper for leaf delivery.

  Records:
    - Delivery latency (histogram)
    - Delivery attempts (counter)
    - Success/failure rate

  Also adds trace logging for debugging."
  (let ((start-time (get-internal-real-time))
        (leaf-id (swarm-id leaf))
        (env-id (envelope-id envelope)))

    ;; Trace: delivery start
    (log:debug "Delivering envelope ~A to leaf ~A"
               env-id leaf-id)

    (handler-case
        (let ((result (call-next-method)))

          ;; Calculate latency
          (let ((latency-ms (/ (* (- (get-internal-real-time) start-time) 1000)
                               internal-time-units-per-second)))

            ;; Record latency
            (record-metric (node-metrics leaf) :delivery-latency-ms latency-ms
                           :type :histogram)

            ;; Record success
            (record-metric (node-metrics leaf) :delivery-success 1 :type :counter)

            ;; Trace: delivery complete
            (log:debug "Delivered envelope ~A to leaf ~A: latency=~Ams"
                       env-id leaf-id latency-ms))

          result)

      (error (e)
        ;; Record failure
        (record-metric (node-metrics leaf) :delivery-error 1 :type :counter)

        ;; Trace: delivery failed
        (log:debug "Delivery failed for envelope ~A to leaf ~A: ~A"
                   env-id leaf-id e)

        ;; Re-signal error
        (error e)))))

;;;; End of file
