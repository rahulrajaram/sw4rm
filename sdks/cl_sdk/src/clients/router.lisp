;;;; router.lisp - Router Service client for SW4RM
;;;;
;;;; Provides message routing capabilities between agents. The router handles
;;;; delivery of envelopes to their intended recipients and supports streaming
;;;; for continuous message reception.

(in-package :sw4rm-sdk)

;;;; Client Class

(defclass router-client (base-client)
  ()
  (:documentation "Client for the SW4RM Router Service.

The router service provides:
- Unary message sending (fire-and-forget or acknowledged)
- Server streaming for continuous message delivery
- Routing metadata and diagnostics

Agents use the router to communicate asynchronously without direct
point-to-point connections."))

;;;; RPC Methods

(defgeneric send-envelope (client envelope)
  (:documentation "Submit a message envelope to the router.

The reference router broadcasts to eligible queues except the producer.
Envelope has no consumer-id or arbitrary metadata field.

Args:
  client: The router-client instance.
  envelope: Plist with envelope fields:
    :producer-id (string) - Agent ID of message sender
    :message-id (string) - Unique message identifier
    :message-type (integer) - Protocol MessageType enum value
    :content-type (string) - Payload media type
    :payload (bytes) - Message payload
    :correlation-id (string, optional) - Correlation/trace ID

Returns:
  Send response plist with :accepted boolean and :reason string.

Signals:
  RPC-ERROR: If send fails.

Example:
  (send-envelope client
                 (list :producer-id \"agent-1\"
                       :message-id \"message-1\"
                       :message-type 2
                       :content-type \"text/plain\"
                       :payload #(72 101 108 108 111)
                       :correlation-id \"wf-123\"))"))

(defmethod send-envelope ((client router-client) envelope)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let* ((request-bytes (encode-send-message-request envelope))
             (response-bytes (grpc-unary-call
                              (client-channel client)
                              "/sw4rm.router.RouterService/SendMessage"
                              request-bytes
                              :deadline-ms (client-timeout-ms client))))
        (decode-send-message-response response-bytes)))))

(defgeneric open-stream (client agent-id handler-fn)
  (:documentation "Open a server-streaming connection for message delivery.

Establishes a persistent server stream between the agent and the router and
receives incoming messages via the handler function. Each envelope passed to
the handler includes :DELIVERY-SEQ from the router StreamItem.

Args:
  client: The router-client instance.
  agent-id: Unique identifier of the agent opening the stream.
  handler-fn: Function called for each incoming message. Takes one argument:
              the envelope plist.

Returns:
  Stream handle (implementation-specific) that can be used to close the stream.

Signals:
  RPC-ERROR: If stream establishment fails.

Example:
  (defun handle-incoming (envelope)
    (format t \"Received: ~A~%\" (getf envelope :message-type)))

  (let ((stream (open-stream client \"agent-1\" #'handle-incoming)))
    ;; Stream is now active, handler-fn will be called for incoming messages
    ;; Use SEND-ENVELOPE on the client for outgoing messages
    ;; ...
    ;; Close stream when done
    (close-stream stream))

Implementation Note:
Server streaming in gRPC requires thread/async handling for the
incoming message loop. The actual implementation will depend on the
chosen gRPC library's streaming API."))

(defmethod open-stream ((client router-client) agent-id handler-fn)
  (ensure-connected client)
  (let ((request-bytes (encode-stream-request agent-id)))
    (grpc-server-stream
     (client-channel client)
     "/sw4rm.router.RouterService/StreamIncoming"
     request-bytes
     (lambda (response-bytes)
       (if response-bytes
             (let ((envelope (decode-stream-item response-bytes)))
             (when envelope
               ;; The envelope includes :DELIVERY-SEQ, copied from the
               ;; StreamItem so the consumer can ACK after side effects.
               (funcall handler-fn envelope)))
           ;; Stream ended — notify handler with NIL
           (funcall handler-fn nil))))))

(defgeneric ack-delivery (client agent-id seq &key message-id permanent-failure)
  (:documentation "Acknowledge a router StreamItem delivery by sequence.

Call this only after the consumer has completed its side effect.  The router
uses the sequence to release the pending row; an unacknowledged row may be
redelivered after its lease expires.  Returns a plist containing :RECORDED.
This method requires the native libgrpc FFI backend; the SDK's placeholder
channel deliberately signals UNIMPLEMENTED when libgrpc is unavailable."))

(defmethod ack-delivery ((client router-client) agent-id seq
                         &key (message-id "") (permanent-failure nil))
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      (let ((request-bytes
              (encode-delivery-ack-request agent-id seq
                                           :message-id message-id
                                           :permanent-failure permanent-failure)))
        (decode-delivery-ack-response
         (grpc-unary-call (client-channel client)
                          "/sw4rm.router.RouterService/AckDelivery"
                          request-bytes
                          :deadline-ms (client-timeout-ms client)))))))

(defgeneric route-info (client agent-id)
  (:documentation "Get routing information and diagnostics for an agent.

Retrieves routing metadata, queue depths, message counts, and other
diagnostics for the specified agent.

Args:
  client: The router-client instance.
  agent-id: Unique identifier of the agent.

Returns:
  Route info plist with:
    :agent-id (string) - Agent identifier
    :pending-messages (integer) - Number of queued messages
    :streams-active (integer) - Number of active streams
    :last-activity (timestamp) - Last message activity

Signals:
  RPC-ERROR: If info retrieval fails.

Example:
  (route-info client \"agent-1\")
  => (:agent-id \"agent-1\"
      :pending-messages 5
      :streams-active 1
      :last-activity \"2026-02-11T10:30:00Z\")"))

(defmethod route-info ((client router-client) agent-id)
  (ensure-connected client)
  (with-retry ((client-retry-max-attempts client))
    (with-deadline ((client-timeout-ms client))
      ;; Stub: In real implementation, this would call gRPC RouterService.RouteInfo
      (error 'rpc-error
             :message "RouteInfo not implemented - requires gRPC integration"
             :status-code "UNIMPLEMENTED" :details "Stub implementation"))))

;;;; Streaming Utilities

(defgeneric close-stream (stream)
  (:documentation "Close an active bidirectional stream.

Cleanly shuts down the stream, flushing any pending messages and
releasing resources.

Args:
  stream: The stream handle returned by OPEN-STREAM.

Returns:
  T on success.

Signals:
  RPC-ERROR: If close fails."))

(defmethod close-stream ((handle stream-handle))
  "Cancel an active server stream via its handle."
  (cancel-stream handle)
  t)
